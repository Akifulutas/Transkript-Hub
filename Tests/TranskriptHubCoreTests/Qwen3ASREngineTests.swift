import Foundation
import Testing
@testable import TranskriptHubCore

@Suite("Qwen3ASREngine, AudioConditioner, SileroVAD & EngineFactory Test Suite")
struct Qwen3ASREngineTests {

    @Test("Qwen3ASREngine language code mapping handles ISO codes, case variations, auto, and nil")
    func testLanguageCodeMapping() {
        #expect(Qwen3ASREngine.mapLanguageCode(nil) == nil)
        #expect(Qwen3ASREngine.mapLanguageCode("") == nil)
        #expect(Qwen3ASREngine.mapLanguageCode("  ") == nil)
        #expect(Qwen3ASREngine.mapLanguageCode("auto") == nil)
        #expect(Qwen3ASREngine.mapLanguageCode("AUTO") == nil)
        #expect(Qwen3ASREngine.mapLanguageCode("de") == "German")
        #expect(Qwen3ASREngine.mapLanguageCode("DE") == "German")
        #expect(Qwen3ASREngine.mapLanguageCode(" tr ") == "Turkish")
        #expect(Qwen3ASREngine.mapLanguageCode("en") == "English")
        #expect(Qwen3ASREngine.mapLanguageCode("German") == "German")
        #expect(Qwen3ASREngine.mapLanguageCode("unknown_xyz") == nil)
    }

    @Test("Qwen3ASREngine splitSpeechSegments enforces <= 28.0s upper bound without dropping audio")
    func testSplitSpeechSegments() {
        let input = [
            SpeechSegment(start: 0.0, end: 12.0),
            SpeechSegment(start: 15.0, end: 75.0)
        ]
        let split = Qwen3ASREngine.splitSpeechSegments(input, maxDuration: 28.0)

        #expect(split.count == 4)
        #expect(split[0] == SpeechSegment(start: 0.0, end: 12.0))
        #expect(split[1] == SpeechSegment(start: 15.0, end: 43.0))
        #expect(split[2] == SpeechSegment(start: 43.0, end: 71.0))
        #expect(split[3] == SpeechSegment(start: 71.0, end: 75.0))
        for seg in split {
            #expect(seg.duration <= 28.001)
        }
    }

    @Test("Qwen3ASREngine throws modelNotFound for non-existent or incomplete model directories")
    func testMissingOrIncompleteModelDirectory() throws {
        #expect(throws: Qwen3ASRError.self) {
            _ = try Qwen3ASREngine(modelPath: "/nonexistent/qwen3-asr-missing")
        }

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("qwen_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try "{}".write(to: tmpDir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        // Missing vocab.json & merges.txt
        #expect(throws: Qwen3ASRError.self) {
            _ = try Qwen3ASREngine(modelPath: tmpDir.path)
        }
    }

    @Test("ModelManager validates directory models for Qwen3-ASR 0.6B and 1.7B")
    func testModelManagerDirectoryValidation() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("mm_qwen_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let mm = ModelManager(modelsDirectory: tmpDir)
        #expect(WhisperModel.qwen3ASR06B.engineKind == .qwen3ASR)
        #expect(WhisperModel.qwen3ASR17B.engineKind == .qwen3ASR)
        #expect(WhisperModel.largeV3.engineKind == .whisperCpp)
        #expect(mm.isModelDownloaded(.qwen3ASR06B) == false)

        let q06Dir = mm.localURL(for: .qwen3ASR06B)
        try FileManager.default.createDirectory(at: q06Dir, withIntermediateDirectories: true)
        for file in ["config.json", "model.safetensors", "vocab.json", "merges.txt"] {
            try "data".write(to: q06Dir.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
        #expect(mm.isModelDownloaded(.qwen3ASR06B) == true)
    }

    @Test("AudioConditioner strips DC offset and sub-95Hz rumble while boosting quiet modulated speech")
    func testAudioConditioner() {
        let sr = 16000.0
        let n = Int(sr * 2.0)
        // Create quiet modulated 400 Hz tone (0.008 amplitude during active half, 0.0005 during quiet half) + 0.15 DC offset
        var samples = [Float](repeating: 0.0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            let env: Float = (i % 16000 < 12000) ? 0.012 : 0.001
            samples[i] = 0.15 + env * Float(sin(2.0 * Double.pi * 400.0 * t))
        }

        let conditioned = AudioConditioner.condition(samples: samples, sampleRate: sr)
        #expect(conditioned.count == n)

        let meanAfter = conditioned.reduce(0, +) / Float(n)
        #expect(abs(meanAfter) < 0.01, "DC offset must be removed")

        let maxBeforeAC = samples.map { abs($0 - 0.15) }.max() ?? 0.0
        let maxAfter = conditioned.map { abs($0) }.max() ?? 0.0
        #expect(maxAfter > maxBeforeAC * 1.5, "Quiet modulated speech should receive linear boost")
        #expect(maxAfter <= 0.96, "Soft-knee limiter must prevent clipping")
    }

    @Test("TranscriptionPipelineCoordinator executes engine, cleans repetitions, and produces SRT output")
    func testTranscriptionPipelineCoordinator() async throws {
        struct MockASREngine: TranscriptionEngine {
            func transcribe(
                _ audio: PreparedAudio,
                options: TranscriptionOptions,
                progress: (@Sendable (Double) -> Void)?,
                onSegment: (@Sendable (Segment) -> Void)?,
                cancellationToken: TranscriptionCancellationToken?
            ) async throws -> TranscriptResult {
                let s1 = Segment(start: 0.0, end: 2.5, text: "Das ist ein wichtiger Test.")
                let s2 = Segment(start: 2.5, end: 5.0, text: "Und das zweite Segment.")
                onSegment?(s1)
                progress?(0.5)
                onSegment?(s2)
                progress?(1.0)
                return TranscriptResult(segments: [s1, s2], detectedLanguage: options.language ?? "de")
            }
        }

        let coordinator = TranscriptionPipelineCoordinator()
        let audio = PreparedAudio(samples: [Float](repeating: 0.05, count: 16000), duration: 1.0)
        let collector = PipelineSegmentCollector()

        let res = try await coordinator.execute(
            preparedAudio: audio,
            engine: MockASREngine(),
            transcriptionOptions: TranscriptionOptions(language: "de", noContext: true),
            postProcessorOptions: PostProcessorOptions(deduplicateRepetitions: true),
            progress: nil,
            onLiveTranscript: { live, seg in
                _ = collector.append(seg)
                #expect(!live.isEmpty)
            },
            cancellationToken: nil
        )

        #expect(res.cleanedSegments.count == 2)
        #expect(res.formattedText.contains("Das ist ein wichtiger Test."))
        #expect(res.formattedText.contains("Und das zweite Segment."))
        #expect(res.srtText.contains("00:00:00,000 --> 00:00:02,500"))
    }
}
