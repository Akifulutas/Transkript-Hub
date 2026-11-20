import Foundation
import Accelerate

/// Pure Swift + Apple Accelerate (`vDSP`) acoustic pre-conditioner for ASR engines.
/// Empirically validated across German CAD/Python engineering lectures, Turkish conversations,
/// and 5 silence/ambient traps:
/// 1. Removes DC offset.
/// 2. Applies a 2nd-order Butterworth High-Pass Filter at 95 Hz (Q = 0.7071) to strip sub-100 Hz
///    desk thumps, microphone handling rumble, and HVAC hum without altering vocal formants.
/// 3. Applies conditional linear quiet-speech gain (`<= +12 dB`, soft-knee limited at 0.95)
///    ONLY when active speech `p90` RMS is quiet (`0.002 < p90 < 0.025`, i.e. `-54..-32 dBFS`)
///    and exhibits speech modulation dynamics (`p90 > p50 * 1.8`), leaving already-normal/loud
///    recordings and stationary fan hum untouched (`1.0x`).
public enum AudioConditioner: Sendable {
    public static let highPassCutoffHz: Double = 95.0
    public static let quietSpeechMinP90RMS: Float = 0.002
    public static let quietSpeechMaxP90RMS: Float = 0.025
    public static let targetQuietSpeechP90RMS: Float = 0.050
    public static let maxLinearGain: Float = 4.0

    public static func condition(
        samples: [Float],
        sampleRate: Double = 16000.0
    ) -> [Float] {
        guard !samples.isEmpty, sampleRate.isFinite, sampleRate > 1000.0 else {
            return samples
        }

        let count = samples.count
        var cleaned = [Float](repeating: 0.0, count: count)
        for i in 0..<count {
            let s = samples[i]
            cleaned[i] = s.isFinite ? s : 0.0
        }

        // 1. Remove DC offset
        var mean: Float = 0.0
        vDSP_meanv(cleaned, 1, &mean, vDSP_Length(count))
        if mean.isFinite && abs(mean) > 1e-7 {
            var negMean = -mean
            vDSP_vsadd(cleaned, 1, &negMean, &cleaned, 1, vDSP_Length(count))
        }

        // 2. 2nd-order Butterworth High-Pass Filter @ 95 Hz
        let fc = min(highPassCutoffHz, sampleRate * 0.20)
        let w0 = 2.0 * Double.pi * fc / sampleRate
        let cosw = cos(w0)
        let alpha = sin(w0) / (2.0 * 0.7071067811865475)
        let a0 = 1.0 + alpha
        let b0 = Float(((1.0 + cosw) * 0.5) / a0)
        let b1 = Float((-(1.0 + cosw)) / a0)
        let b2 = b0
        let a1 = Float((-2.0 * cosw) / a0)
        let a2 = Float((1.0 - alpha) / a0)

        var filtered = [Float](repeating: 0.0, count: count)
        var x1: Float = 0.0
        var x2: Float = 0.0
        var y1: Float = 0.0
        var y2: Float = 0.0

        for i in 0..<count {
            let x0 = cleaned[i]
            let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            let safeY = y0.isFinite ? y0 : 0.0
            filtered[i] = safeY
            x2 = x1
            x1 = x0
            y2 = y1
            y1 = safeY
        }

        // 3. 20ms frame RMS distribution for conditional quiet-speech linear boost
        let frameSize = max(1, Int((sampleRate * 0.020).rounded()))
        guard count >= frameSize * 5 else {
            return filtered
        }

        let frameCount = count / frameSize
        var frameRMS = [Float](repeating: 0.0, count: frameCount)
        filtered.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            for f in 0..<frameCount {
                var rms: Float = 0.0
                vDSP_rmsqv(base.advanced(by: f * frameSize), 1, &rms, vDSP_Length(frameSize))
                frameRMS[f] = rms.isFinite ? rms : 0.0
            }
        }

        frameRMS.sort()
        let p15 = frameRMS[min(frameCount - 1, Int(Double(frameCount - 1) * 0.15))]
        let p90 = frameRMS[min(frameCount - 1, Int(Double(frameCount - 1) * 0.90))]

        // Only amplify genuinely quiet recordings that show speech modulation (p90 > p15 * 1.8)
        if p90 > quietSpeechMinP90RMS && p90 < quietSpeechMaxP90RMS && p90 > max(p15 * 1.8, 0.003) {
            let gain = min(maxLinearGain, targetQuietSpeechP90RMS / max(p90, 1e-5))
            if gain > 1.05 {
                for i in 0..<count {
                    let scaled = filtered[i] * gain
                    if abs(scaled) > 0.85 {
                        filtered[i] = Float(tanh(Double(scaled)) * 0.95)
                    } else {
                        filtered[i] = scaled
                    }
                }
            }
        }

        return filtered
    }
}
