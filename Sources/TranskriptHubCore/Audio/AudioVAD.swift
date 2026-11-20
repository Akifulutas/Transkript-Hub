import Foundation
import Accelerate

public struct SpeechSegment: Sendable, Codable, Equatable, Hashable {
    public let start: Double
    public let end: Double

    public var duration: Double {
        max(0.0, end - start)
    }

    public init(start: Double, end: Double) {
        let safeStart = start.isFinite ? max(0.0, start) : 0.0
        let safeEnd = end.isFinite ? max(safeStart, end) : safeStart
        self.start = safeStart
        self.end = safeEnd
    }
}

public enum AudioVAD: Sendable {
    public static let frameDurationSeconds: Double = 0.020
    public static let minSpeechRMS: Float = 0.012
    public static let maxNoiseFloorRMS: Float = 0.015
    public static let noiseMultiplier: Float = 3.0
    public static let minConsecutiveActiveFrames: Int = 2
    public static let bridgeGapSeconds: Double = 0.800
    public static let prePadSeconds: Double = 0.300
    public static let postPadSeconds: Double = 0.500

    /// Detects speech segments in mono Float32 PCM audio using adaptive RMS energy thresholding.
    /// Pipeline order:
    /// 1. Group contiguous active 20ms frames into raw intervals.
    /// 2. Bridge silence gaps < 800ms BEFORE applying boundary padding.
    /// 3. Apply 300ms pre-pad and 500ms post-pad, clamped to [0.0, totalDuration].
    /// 4. Merge overlapping padded intervals.
    public static func detectSpeech(
        samples: [Float],
        sampleRate: Double = 16000.0
    ) -> [SpeechSegment] {
        guard !samples.isEmpty, sampleRate.isFinite, sampleRate > 0 else {
            return []
        }

        let frameSize = Int((sampleRate * frameDurationSeconds).rounded())
        guard frameSize > 0, samples.count >= frameSize else {
            return []
        }

        let totalDuration = Double(samples.count) / sampleRate
        let fullFrames = samples.count / frameSize
        let remainder = samples.count % frameSize
        let totalFrames = fullFrames + (remainder > 0 ? 1 : 0)

        var frameRMS = [Float](repeating: 0.0, count: totalFrames)
        var maxFrameRMS: Float = 0.0

        samples.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            for frameIndex in 0..<totalFrames {
                let offset = frameIndex * frameSize
                let count = min(frameSize, samples.count - offset)
                guard count > 0 else { continue }

                var rms: Float = 0.0
                vDSP_rmsqv(baseAddress.advanced(by: offset), 1, &rms, vDSP_Length(count))
                let sanitized: Float
                if rms.isFinite {
                    sanitized = rms
                } else {
                    var sumSq: Double = 0.0
                    var finiteCount = 0
                    for k in 0..<count {
                        let sample = baseAddress[offset + k]
                        if sample.isFinite {
                            let d = Double(sample)
                            sumSq += d * d
                            finiteCount += 1
                        }
                    }
                    if finiteCount > 0 {
                        let fallback = Float(sqrt(sumSq / Double(count)))
                        sanitized = fallback.isFinite ? fallback : 0.0
                    } else {
                        sanitized = 0.0
                    }
                }
                frameRMS[frameIndex] = sanitized
                if sanitized > maxFrameRMS {
                    maxFrameRMS = sanitized
                }
            }
        }

        // Reject digital silence and stationary very-low-level noise immediately
        guard maxFrameRMS >= minSpeechRMS else {
            return []
        }

        // Estimate noise floor exclusively from sub-speech frames (< minSpeechRMS) so that
        // quiet speech (>= minSpeechRMS, e.g. 0.012..0.044) can never self-threshold even when
        // true silence is < 2% (including 0% or 1.5%) alongside loud speech (>= 0.045..0.25).
        var subSpeechFrames: [Float] = []
        for rms in frameRMS where rms < minSpeechRMS {
            subSpeechFrames.append(rms)
        }

        let minNoiseAdaptationFrames = max(5, totalFrames / 20)
        let elevatedNoiseFloorMin: Float = 0.008
        let maxAdaptiveThresholdRMS: Float = 0.014
        let threshold: Float
        if subSpeechFrames.count >= minNoiseAdaptationFrames {
            subSpeechFrames.sort()
            let noiseMedian = subSpeechFrames[subSpeechFrames.count / 2]
            if noiseMedian > elevatedNoiseFloorMin {
                let p90Index = min(subSpeechFrames.count - 1, Int(Double(subSpeechFrames.count - 1) * 0.90))
                let noiseSpread = max(0.0, subSpeechFrames[p90Index] - noiseMedian)
                let adaptiveCandidate = noiseMedian + max(noiseSpread * noiseMultiplier, noiseMedian * 0.25)
                threshold = min(maxAdaptiveThresholdRMS, max(minSpeechRMS, adaptiveCandidate))
            } else {
                threshold = minSpeechRMS
            }
        } else {
            threshold = minSpeechRMS
        }

        // Step 1: Collect raw contiguous active frame intervals (>= 2 consecutive frames / 40ms for impulse rejection)
        var rawIntervals: [(start: Double, end: Double)] = []
        var activeStartFrame: Int? = nil

        for frameIndex in 0..<totalFrames {
            let isActive = frameRMS[frameIndex] >= threshold
            if isActive {
                if activeStartFrame == nil {
                    activeStartFrame = frameIndex
                }
            } else if let startFrame = activeStartFrame {
                if (frameIndex - startFrame) >= minConsecutiveActiveFrames {
                    let rawStart = Double(startFrame * frameSize) / sampleRate
                    let rawEnd = Double(min(samples.count, frameIndex * frameSize)) / sampleRate
                    rawIntervals.append((start: rawStart, end: rawEnd))
                }
                activeStartFrame = nil
            }
        }

        if let startFrame = activeStartFrame, (totalFrames - startFrame) >= minConsecutiveActiveFrames {
            let rawStart = Double(startFrame * frameSize) / sampleRate
            let rawEnd = totalDuration
            rawIntervals.append((start: rawStart, end: rawEnd))
        }

        guard !rawIntervals.isEmpty else {
            return []
        }

        // Step 2: Bridge silence gaps < 800ms BEFORE boundary padding
        var bridgedIntervals: [(start: Double, end: Double)] = []
        bridgedIntervals.reserveCapacity(rawIntervals.count)
        for interval in rawIntervals {
            if let last = bridgedIntervals.last, (interval.start - last.end) < bridgeGapSeconds {
                bridgedIntervals[bridgedIntervals.count - 1].end = max(last.end, interval.end)
            } else {
                bridgedIntervals.append(interval)
            }
        }

        // Step 3: Apply boundary padding (300ms pre-pad, 500ms post-pad) clamped to [0.0, totalDuration]
        let paddedIntervals = bridgedIntervals.map { interval in
            (
                start: max(0.0, interval.start - prePadSeconds),
                end: min(totalDuration, interval.end + postPadSeconds)
            )
        }

        // Step 4: Merge overlapping or touching padded intervals
        var mergedSegments: [SpeechSegment] = []
        mergedSegments.reserveCapacity(paddedIntervals.count)
        for interval in paddedIntervals {
            if let last = mergedSegments.last, interval.start <= last.end {
                mergedSegments[mergedSegments.count - 1] = SpeechSegment(
                    start: last.start,
                    end: max(last.end, interval.end)
                )
            } else {
                mergedSegments.append(SpeechSegment(start: interval.start, end: interval.end))
            }
        }

        return mergedSegments
    }
}
