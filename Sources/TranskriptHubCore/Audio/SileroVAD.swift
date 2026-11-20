import Foundation
import whisper

/// Neural Voice Activity Detection powered by `whisper.xcframework`'s built-in Silero VAD v6.2.0 C API.
/// Runs ~170x-260x faster than real-time on Apple Silicon CPU BLAS while rejecting non-speech noise traps
/// (desk thumps, mouse clicks, fan hum) that energy/RMS detectors cannot separate from quiet speech.
public enum SileroVAD: Sendable {
    public static let modelFileName = "ggml-silero-v6.2.0.bin"
    public static let downloadURL = URL(string: "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v6.2.0.bin")!
    public static let minValidModelBytes: Int64 = 500_000

    /// Resolves the local Silero VAD GGML model path if available on disk.
    public static func defaultModelPath() -> String? {
        let fm = FileManager.default
        var candidates: [URL] = []

        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            candidates.append(
                appSupport
                    .appendingPathComponent("TranskriptHub/Models", isDirectory: true)
                    .appendingPathComponent(modelFileName)
            )
        }
        candidates.append(URL(fileURLWithPath: "/tmp/stt_benchmark/\(modelFileName)"))

        for url in candidates {
            if fm.fileExists(atPath: url.path),
               let attrs = try? fm.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64,
               size >= minValidModelBytes {
                return url.path
            }
        }
        return nil
    }

    /// Detects speech intervals using Silero VAD v6.2.0, returning nil only if the VAD model
    /// is unavailable or cannot be initialized (allowing caller to fall back to `AudioVAD.detectSpeech`).
    public static func detectSpeech(
        samples: [Float],
        sampleRate: Double = 16000.0,
        modelPath: String? = nil,
        threshold: Float = 0.35,
        minSpeechDurationMs: Int32 = 200,
        minSilenceDurationMs: Int32 = 500,
        maxSpeechDurationSeconds: Float = 28.0,
        speechPadMs: Int32 = 250
    ) -> [SpeechSegment]? {
        guard !samples.isEmpty, sampleRate.isFinite, sampleRate > 0 else {
            return []
        }

        guard let resolvedPath = modelPath ?? defaultModelPath(),
              FileManager.default.fileExists(atPath: resolvedPath) else {
            return nil
        }

        var cparams = whisper_vad_default_context_params()
        cparams.use_gpu = false
        cparams.n_threads = Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount)))

        guard let vctx = whisper_vad_init_from_file_with_params(resolvedPath, cparams) else {
            return nil
        }
        defer {
            whisper_vad_free(vctx)
        }

        var vparams = whisper_vad_default_params()
        vparams.threshold = threshold
        vparams.min_speech_duration_ms = minSpeechDurationMs
        vparams.min_silence_duration_ms = minSilenceDurationMs
        vparams.max_speech_duration_s = maxSpeechDurationSeconds
        vparams.speech_pad_ms = speechPadMs
        vparams.samples_overlap = 0.10

        let totalDuration = Double(samples.count) / sampleRate

        let rawSegmentsPtr: OpaquePointer? = samples.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return nil }
            return whisper_vad_segments_from_samples(vctx, vparams, base, Int32(samples.count))
        }

        guard let segs = rawSegmentsPtr else {
            return nil
        }
        defer {
            whisper_vad_free_segments(segs)
        }

        let nSegs = whisper_vad_segments_n_segments(segs)
        guard nSegs > 0 else {
            return []
        }

        // Note: whisper_vad_segments_get_segment_t0/t1 return centiseconds (100.0 == 1.0s)
        var extracted: [SpeechSegment] = []
        extracted.reserveCapacity(Int(nSegs))

        for i in 0..<nSegs {
            let t0Sec = max(0.0, Double(whisper_vad_segments_get_segment_t0(segs, i)) / 100.0)
            let t1Sec = min(totalDuration, Double(whisper_vad_segments_get_segment_t1(segs, i)) / 100.0)
            guard t1Sec > t0Sec else { continue }
            extracted.append(SpeechSegment(start: t0Sec, end: t1Sec))
        }

        // Bridge short pauses (< 0.80s) only when combined segment stays <= maxSpeechDurationSeconds
        let maxDur = Double(maxSpeechDurationSeconds)
        var merged: [SpeechSegment] = []
        merged.reserveCapacity(extracted.count)

        for seg in extracted {
            if let last = merged.last,
               (seg.start - last.end) < AudioVAD.bridgeGapSeconds,
               (max(last.end, seg.end) - last.start) <= maxDur {
                merged[merged.count - 1] = SpeechSegment(start: last.start, end: max(last.end, seg.end))
            } else {
                merged.append(seg)
            }
        }

        return merged
    }
}
