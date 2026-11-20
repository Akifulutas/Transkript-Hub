import Foundation
import CQwenASR

public enum Qwen3ASRError: Error, LocalizedError, Equatable {
    case modelNotFound(String)
    case modelLoadFailed(String)
    case transcriptionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "Qwen3-ASR model dizini bulunamadı: \(path)"
        case .modelLoadFailed(let path):
            return "Qwen3-ASR modeli yüklenemedi: \(path)"
        case .transcriptionFailed(let reason):
            return "Qwen3-ASR transkripsiyon hatası: \(reason)"
        }
    }
}

/// Native pure-C Qwen3-ASR (0.6B / 1.7B) transcription engine backed by Apple Accelerate (`CQwenASR`).
/// Enforces `AudioConditioner` + `SileroVAD`/`AudioVAD` speech detection + `<= 28.0s` chunking
/// to guarantee zero repetition loops and zero silence hallucinations on long recordings.
public actor Qwen3ASREngine: TranscriptionEngine {
    public static let maxChunkSeconds: Double = 28.0

    /// Process-wide serialization lock protecting `CQwenASR` global thread pool (`qwen_set_threads` / `parallel_for`).
    private static let cBackendExecutionLock = NSLock()

    private let modelPath: String
    private nonisolated(unsafe) var context: UnsafeMutablePointer<qwen_ctx_t>?

    public init(modelPath: String) throws {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: modelPath, isDirectory: &isDir)
        guard exists else {
            throw Qwen3ASRError.modelNotFound(modelPath)
        }

        let requiredFiles = ["config.json", "vocab.json", "merges.txt"]
        if isDir.boolValue {
            for req in requiredFiles {
                let path = (modelPath as NSString).appendingPathComponent(req)
                if !FileManager.default.fileExists(atPath: path) {
                    throw Qwen3ASRError.modelNotFound(path)
                }
            }
        }

        guard let ctx = qwen_load(modelPath) else {
            throw Qwen3ASRError.modelLoadFailed(modelPath)
        }

        ctx.pointee.segment_sec = 0.0
        ctx.pointee.skip_silence = 0
        ctx.pointee.past_text_conditioning = 0
        self.modelPath = modelPath
        self.context = ctx
    }

    deinit {
        if let ctx = context {
            qwen_free(ctx)
        }
    }

    /// Maps ISO-639-1 codes (`"de"`, `"tr"`, `"en"`, etc.) to Qwen3-ASR canonical language names.
    public nonisolated static func mapLanguageCode(_ language: String?) -> String? {
        guard let trimmed = language?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed.lowercased() != "auto" else {
            return nil
        }

        let lower = trimmed.lowercased()
        let table: [String: String] = [
            "de": "German",
            "tr": "Turkish",
            "en": "English",
            "fr": "French",
            "es": "Spanish",
            "it": "Italian",
            "pt": "Portuguese",
            "nl": "Dutch",
            "ru": "Russian",
            "ar": "Arabic",
            "zh": "Chinese",
            "ja": "Japanese",
            "ko": "Korean",
            "pl": "Polish"
        ]
        if let mapped = table[lower] {
            return mapped
        }
        if let match = table.values.first(where: { $0.lowercased() == lower }) {
            return match
        }
        return nil
    }

    /// Splits speech intervals so no chunk sent to Qwen3-ASR exceeds `maxDuration` seconds (default 28.0s).
    public nonisolated static func splitSpeechSegments(
        _ segments: [SpeechSegment],
        maxDuration: Double = Qwen3ASREngine.maxChunkSeconds
    ) -> [SpeechSegment] {
        let safeMax = max(1.0, maxDuration)
        var out: [SpeechSegment] = []
        out.reserveCapacity(segments.count)

        for seg in segments where seg.duration > 0.01 {
            if seg.duration <= safeMax {
                out.append(seg)
            } else {
                var cursor = seg.start
                while cursor < seg.end - 0.01 {
                    let nextEnd = min(seg.end, cursor + safeMax)
                    out.append(SpeechSegment(start: cursor, end: nextEnd))
                    cursor = nextEnd
                }
            }
        }
        return out
    }

    public func transcribe(
        _ audio: PreparedAudio,
        options: TranscriptionOptions = TranscriptionOptions(),
        progress: (@Sendable (Double) -> Void)? = nil,
        onSegment: (@Sendable (Segment) -> Void)? = nil,
        cancellationToken: TranscriptionCancellationToken? = nil
    ) async throws -> TranscriptResult {
        if cancellationToken?.isCancelled == true || Task.isCancelled {
            throw CancellationError()
        }

        guard !audio.samples.isEmpty else {
            throw WhisperCppError.emptyAudio
        }

        guard let ctx = context else {
            throw Qwen3ASRError.modelLoadFailed(modelPath)
        }

        let sampleRate = AudioDecoder.targetSampleRate
        let totalSamples = audio.samples.count
        let totalDuration = Double(totalSamples) / sampleRate

        // 1. Acoustic conditioning (DC removal + 95 Hz Butterworth high-pass + conditional quiet speech gain)
        let conditioned = AudioConditioner.condition(samples: audio.samples, sampleRate: sampleRate)

        // 2. VAD + mandatory <=28s chunking
        let rawSegments: [SpeechSegment]
        if options.useVAD {
            let rmsSegments = AudioVAD.detectSpeech(samples: conditioned, sampleRate: sampleRate)
            if rmsSegments.isEmpty {
                progress?(1.0)
                return TranscriptResult(segments: [], detectedLanguage: nil)
            }
            if let sileroSegments = SileroVAD.detectSpeech(
                samples: conditioned,
                sampleRate: sampleRate,
                maxSpeechDurationSeconds: Float(Self.maxChunkSeconds)
            ) {
                rawSegments = sileroSegments
            } else {
                rawSegments = rmsSegments
            }
        } else {
            rawSegments = [SpeechSegment(start: 0.0, end: totalDuration)]
        }

        let speechChunks = Self.splitSpeechSegments(rawSegments, maxDuration: Self.maxChunkSeconds)
        if speechChunks.isEmpty {
            progress?(1.0)
            return TranscriptResult(segments: [], detectedLanguage: nil)
        }

        // 3. Configure Qwen3-ASR context parameters
        let threads = Int32(max(1, options.threads))
        Self.cBackendExecutionLock.withLock {
            qwen_set_threads(threads)
            ctx.pointee.past_text_conditioning = options.noContext ? 0 : 1
            ctx.pointee.segment_sec = 0.0
            ctx.pointee.skip_silence = 0

            if let mappedLang = Self.mapLanguageCode(options.language) {
                _ = mappedLang.withCString { qwen_set_force_language(ctx, $0) }
            } else {
                _ = qwen_set_force_language(ctx, nil)
            }

            let trimmedPrompt = options.initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let prompt = trimmedPrompt, !prompt.isEmpty {
                _ = prompt.withCString { qwen_set_prompt(ctx, $0) }
            } else {
                _ = qwen_set_prompt(ctx, nil)
            }
        }

        var slices: [(range: Range<Int>, startSec: Double, endSec: Double)] = []
        slices.reserveCapacity(speechChunks.count)
        for chunk in speechChunks {
            let sIdx = max(0, min(totalSamples, Int((chunk.start * sampleRate).rounded(.down))))
            let eIdx = max(sIdx, min(totalSamples, Int((chunk.end * sampleRate).rounded(.up))))
            if eIdx > sIdx {
                slices.append((range: sIdx..<eIdx, startSec: Double(sIdx) / sampleRate, endSec: Double(eIdx) / sampleRate))
            }
        }

        if slices.isEmpty {
            progress?(1.0)
            return TranscriptResult(segments: [], detectedLanguage: nil)
        }

        let totalSpeechSamples = max(1, slices.reduce(0) { $0 + $1.range.count })
        var processedSamples = 0
        var outputSegments: [Segment] = []
        progress?(0.0)

        for slice in slices {
            if cancellationToken?.isCancelled == true || Task.isCancelled {
                throw CancellationError()
            }

            let sliceCount = slice.range.count
            let rawText: String = conditioned[slice.range].withUnsafeBufferPointer { buf in
                Self.cBackendExecutionLock.withLock {
                    qwen_set_threads(threads)
                    guard let base = buf.baseAddress,
                          let cStr = qwen_transcribe_audio(ctx, base, Int32(sliceCount)) else {
                        return ""
                    }
                    defer { free(cStr) }
                    return String(cString: cStr)
                }
            }

            if cancellationToken?.isCancelled == true || Task.isCancelled {
                throw CancellationError()
            }

            let cleanedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanedText.isEmpty {
                let words = Segment.interpolateWords(for: cleanedText, start: slice.startSec, end: slice.endSec)
                let seg = Segment(
                    start: slice.startSec,
                    end: slice.endSec,
                    text: cleanedText,
                    speaker: nil,
                    words: words,
                    noSpeechProb: 0.0
                )
                outputSegments.append(seg)
                onSegment?(seg)
            }

            processedSamples += sliceCount
            let ratio = min(1.0, max(0.0, Double(processedSamples) / Double(totalSpeechSamples)))
            progress?(ratio)
        }

        progress?(1.0)
        let normalizedLang = WhisperCppEngine.normalizeLanguage(options.language)
        return TranscriptResult(segments: outputSegments, detectedLanguage: normalizedLang)
    }
}
