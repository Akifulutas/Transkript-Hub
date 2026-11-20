import Foundation
import Testing
import whisper
@testable import TranskriptHubCore

@Suite("E2E Tier 1: Feature Coverage")
struct E2EFeatureTests {

    // MARK: - F1: AudioVAD Engine (5 tests)

    @Test("Tier 1 F1.1: VAD rejects pure digital silence")
    func testTier1_VAD_SilenceRejection() {
        let silence = E2ETestHelpers.makeSilence(seconds: 3.0)
        #expect(silence.count == 48_000)

        let segments = AudioVAD.detectSpeech(samples: silence, sampleRate: E2ETestHelpers.defaultSampleRate)
        #expect(segments.isEmpty, "Pure digital silence must yield 0 speech segments")
    }

    @Test("Tier 1 F1.2: VAD detects continuous speech burst with >=300ms pre-pad and >=500ms post-pad")
    func testTier1_VAD_ContinuousSpeechBurstDetection() {
        let audio =
            E2ETestHelpers.makeSilence(seconds: 2.0) +
            E2ETestHelpers.makeSineWave(seconds: 2.0, frequency: 1000.0, targetRMS: 0.35) +
            E2ETestHelpers.makeSilence(seconds: 2.0)

        let segments = AudioVAD.detectSpeech(samples: audio, sampleRate: E2ETestHelpers.defaultSampleRate)
        #expect(segments.count == 1, "Expected 1 speech segment for single burst, got \(segments.count)")
        if let seg = segments.first {
            #expect(seg.start <= 1.705, "Expected >= 300ms pre-pad before 2.0s onset, got start=\(seg.start)")
            #expect(seg.end >= 4.495, "Expected >= 500ms post-pad after 4.0s offset, got end=\(seg.end)")
            #expect(seg.start >= 0.0)
            #expect(seg.end <= 6.0)
            #expect(seg.duration >= 2.79)
        }
    }

    @Test("Tier 1 F1.3: VAD bridges silence gap under 800ms into a single segment")
    func testTier1_VAD_SilenceBridgingUnderThreshold() {
        let audio =
            E2ETestHelpers.makeSilence(seconds: 1.0) +
            E2ETestHelpers.makeSineWave(seconds: 1.0, targetRMS: 0.35) +
            E2ETestHelpers.makeSilence(seconds: 0.5) +
            E2ETestHelpers.makeSineWave(seconds: 1.0, targetRMS: 0.35) +
            E2ETestHelpers.makeSilence(seconds: 1.5)

        let segments = AudioVAD.detectSpeech(samples: audio, sampleRate: E2ETestHelpers.defaultSampleRate)
        #expect(segments.count == 1, "500ms gap (< 800ms bridge threshold) should merge into 1 segment")
        if let seg = segments.first {
            #expect(seg.start <= 0.705)
            #expect(seg.end >= 3.995)
        }
    }

    @Test("Tier 1 F1.4: VAD splits speech bursts separated by >800ms silence")
    func testTier1_VAD_SilenceSplitOverThreshold() {
        let audio =
            E2ETestHelpers.makeSilence(seconds: 1.0) +
            E2ETestHelpers.makeSineWave(seconds: 1.0, targetRMS: 0.35) +
            E2ETestHelpers.makeSilence(seconds: 1.2) +
            E2ETestHelpers.makeSineWave(seconds: 1.0, targetRMS: 0.35) +
            E2ETestHelpers.makeSilence(seconds: 1.0)

        let segments = AudioVAD.detectSpeech(samples: audio, sampleRate: E2ETestHelpers.defaultSampleRate)
        #expect(segments.count == 2, "1200ms gap (> 800ms bridge threshold) should produce 2 distinct segments")
        if segments.count == 2 {
            #expect(segments[0].end <= segments[1].start)
            #expect(segments[0].start <= 0.705)
            #expect(segments[1].end >= 4.695)
        }
    }

    @Test("Tier 1 F1.5: VAD adapts to low noise floor and isolates high-energy speech burst")
    func testTier1_VAD_EnergyAdaptationWithNoiseFloor() {
        let noiseFloor = E2ETestHelpers.makeDeterministicNoise(seconds: 6.0, targetRMS: 0.005)
        let leadingSilence = E2ETestHelpers.makeSilence(seconds: 2.0)
        let speechBurst = E2ETestHelpers.makeSineWave(seconds: 1.5, frequency: 800.0, targetRMS: 0.40)
        let audio = E2ETestHelpers.mix(noiseFloor, leadingSilence + speechBurst)

        let segments = AudioVAD.detectSpeech(samples: audio, sampleRate: E2ETestHelpers.defaultSampleRate)
        #expect(segments.count == 1, "Noise floor (RMS 0.005) must not trigger speech outside the RMS 0.40 burst")
        if let seg = segments.first {
            #expect(seg.start >= 0.5 && seg.start <= 1.75)
            #expect(seg.end >= 3.95 && seg.end <= 5.0)
        }
    }

    // MARK: - F2: WhisperCppEngine Parameter Wiring (5 tests)

    @Test("Tier 1 F2.1: Default TranscriptionOptions enforce anti-hallucination defaults")
    func testTier1_Options_DefaultAntiHallucinationSettings() {
        let options = TranscriptionOptions()
        #expect(options.suppressBlank == true)
        #expect(options.suppressNonSpeech == true)
        #expect(abs(options.noSpeechThreshold - 0.60) < 0.001)
        #expect(options.tokenTimestamps == true)
        #expect(options.useVAD == true)
        #expect(options.noContext == true)
        #expect(abs(options.entropyThreshold - 2.4) < 0.001)
    }

    @Test("Tier 1 F2.2: TranscriptionOptions map directly to whisper_full_params C fields")
    func testTier1_Options_ParameterMappingToWparams() {
        let options = TranscriptionOptions(
            noContext: true,
            suppressBlank: false,
            suppressNonSpeech: true,
            noSpeechThreshold: 0.75,
            entropyThreshold: 2.6
        )
        WhisperCppEngine.withWhisperParams(options: options) { wparams in
            #expect(wparams.no_context == true)
            #expect(wparams.suppress_blank == false)
            #expect(wparams.suppress_nst == true)
            #expect(abs(wparams.no_speech_thold - 0.75) < 0.001)
            #expect(abs(wparams.entropy_thold - 2.6) < 0.001)
        }
    }

    @Test("Tier 1 F2.3: Initial prompt and carry_initial_prompt map to whisper_full_params")
    func testTier1_Options_InitialPromptAndCarry() {
        let options = TranscriptionOptions(initialPrompt: "CAD, Turbinenrad, Mesh")
        WhisperCppEngine.withWhisperParams(options: options) { wparams in
            #expect(wparams.initial_prompt != nil)
            if let ptr = wparams.initial_prompt {
                #expect(String(cString: ptr) == "CAD, Turbinenrad, Mesh")
            }
            #expect(wparams.carry_initial_prompt == true)
        }
    }

    @Test("Tier 1 F2.4: Pre-cancelled TranscriptionCancellationToken aborts before decoding")
    func testTier1_Engine_CancellationHandling() async throws {
        let token = TranscriptionCancellationToken()
        #expect(token.isCancelled == false)
        token.cancel()
        #expect(token.isCancelled == true)

        let engine = MockTranscriptionEngine(segments: [
            Segment(start: 0.0, end: 1.0, text: "Should never execute")
        ])
        let audio = PreparedAudio(samples: E2ETestHelpers.makeSineWave(seconds: 1.0), duration: 1.0)

        let segmentCallbackInvoked = AtomicBoolFlag()
        await #expect(throws: CancellationError.self) {
            _ = try await engine.transcribe(
                audio,
                options: TranscriptionOptions(language: "de", noContext: true),
                onSegment: { _ in segmentCallbackInvoked.setTrue() },
                cancellationToken: token
            )
        }
        #expect(segmentCallbackInvoked.value == false)
        #expect(throws: WhisperCppError.self) {
            _ = try WhisperCppEngine(modelPath: "/nonexistent/ggml-missing-\(UUID().uuidString).bin")
        }
    }

    @Test("Tier 1 F2.5: Empty audio buffer throws WhisperCppError.emptyAudio")
    func testTier1_Engine_EmptyAudioValidation() async throws {
        let emptyAudio = PreparedAudio(samples: [], duration: 0.0)

        let mockEngine = MockTranscriptionEngine(segments: [])
        do {
            _ = try await mockEngine.transcribe(emptyAudio, options: TranscriptionOptions())
            Issue.record("Expected MockTranscriptionEngine to throw WhisperCppError.emptyAudio")
        } catch let error as WhisperCppError {
            if case .emptyAudio = error {
                // Expected
            } else {
                Issue.record("Expected WhisperCppError.emptyAudio, got \(error)")
            }
        }

        // Verify production WhisperCppEngine empty-audio validation when a local GGML model is present
        let modelManager = ModelManager()
        let preferredModels: [WhisperModel] = [
            .tiny, .base, .small, .medium, .largeV3TurboQ5, .largeV3Q5, .largeV3Turbo, .largeV3
        ]
        if let availableModel = preferredModels.first(where: { modelManager.isModelDownloaded($0) }) {
            let modelURL = modelManager.localURL(for: availableModel)
            let realEngine = try WhisperCppEngine(modelPath: modelURL.path)
            do {
                _ = try await realEngine.transcribe(emptyAudio, options: TranscriptionOptions())
                Issue.record("Expected WhisperCppEngine to throw WhisperCppError.emptyAudio on empty samples")
            } catch let error as WhisperCppError {
                if case .emptyAudio = error {
                    // Expected production guard
                } else {
                    Issue.record("Expected WhisperCppError.emptyAudio from WhisperCppEngine, got \(error)")
                }
            }
        }

        #expect(WhisperCppError.emptyAudio.errorDescription?.isEmpty == false)
    }

    // MARK: - F3: TranscriptPostProcessor Hardening (5 tests)

    @Test("Tier 1 F3.1: Standalone pure hallucination phrase is pruned completely")
    func testTier1_PostProcessor_StandalonePureHallucinationPruned() {
        let processor = TranscriptPostProcessor()
        let segments = [
            Segment(start: 0.0, end: 2.5, text: "Es heilt die göttliche Kraft.")
        ]

        let processedSegments = processor.processSegments(segments: segments, options: PostProcessorOptions())
        let processedText = processor.process(segments: segments, options: PostProcessorOptions())

        #expect(processedSegments.isEmpty)
        #expect(processedText.isEmpty)
    }

    @Test("Tier 1 F3.2: Standalone known hallucination phrase is pruned on first occurrence")
    func testTier1_PostProcessor_StandaloneKnownHallucinationPruned() {
        let processor = TranscriptPostProcessor()
        let segments = [
            Segment(start: 0.0, end: 3.0, text: "Vielen Dank für Ihre Aufmerksamkeit.")
        ]

        let processedSegments = processor.processSegments(segments: segments, options: PostProcessorOptions())
        let processedText = processor.process(segments: segments, options: PostProcessorOptions())

        #expect(processedSegments.isEmpty, "Single standalone known hallucination must be pruned")
        #expect(processedText.isEmpty, "Single standalone known hallucination must yield empty string")
    }

    @Test("Tier 1 F3.3: Consecutive identical repetition loop across segments is collapsed")
    func testTier1_PostProcessor_ConsecutiveIdenticalRepetitionLoopCollapsed() {
        let processor = TranscriptPostProcessor()
        let segments = (0..<5).map { idx in
            Segment(start: Double(idx), end: Double(idx + 1), text: "CAD-Modellierung.")
        }

        let processedSegments = processor.processSegments(segments: segments, options: PostProcessorOptions())
        #expect(!processedSegments.isEmpty)
        #expect(processedSegments.count <= 2, "5 identical segments must collapse to <= 2 occurrences")
        #expect(processedSegments.first?.text == "CAD-Modellierung.")
    }

    @Test("Tier 1 F3.4: Intra-segment repeating clause is deduplicated to a single instance")
    func testTier1_PostProcessor_IntraSegmentRepeatingClauseDeduplicated() {
        let processor = TranscriptPostProcessor()
        let segments = [
            Segment(
                start: 0.0,
                end: 6.0,
                text: "wir analysieren das Netz, wir analysieren das Netz, wir analysieren das Netz."
            )
        ]

        let deduplicatedText = processor.deduplicatePhrases(segments[0].text)
        let occurrencesText = deduplicatedText.components(separatedBy: "wir analysieren das Netz").count - 1
        #expect(occurrencesText == 1)

        let processedSegments = processor.processSegments(segments: segments, options: PostProcessorOptions())
        #expect(processedSegments.count == 1)
        if let first = processedSegments.first {
            let count = first.text.components(separatedBy: "wir analysieren das Netz").count - 1
            #expect(count == 1)
        }
    }

    @Test("Tier 1 F3.5: Surviving segments preserve original start and end timestamps when middle segment is pruned")
    func testTier1_PostProcessor_SegmentTimestampPreservation() {
        let processor = TranscriptPostProcessor()
        let segments = [
            Segment(start: 1.2, end: 4.5, text: "Erster Schritt."),
            Segment(start: 5.0, end: 7.0, text: "Es heilt die göttliche Kraft."),
            Segment(start: 10.0, end: 14.2, text: "Zweiter Schritt.")
        ]

        let processed = processor.processSegments(segments: segments, options: PostProcessorOptions())
        #expect(processed.count == 2)
        if processed.count == 2 {
            #expect(processed[0].start == 1.2)
            #expect(processed[0].end == 4.5)
            #expect(processed[0].text == "Erster Schritt.")
            #expect(processed[1].start == 10.0)
            #expect(processed[1].end == 14.2)
            #expect(processed[1].text == "Zweiter Schritt.")
        }
    }

    // MARK: - F4: SRTFormatter & Subtitle Exporter (5 tests)

    @Test("Tier 1 F4.1: SRTFormatter formats timecodes with HH:mm:ss,SSS millisecond precision")
    func testTier1_SRT_TimecodeFormattingPrecision() {
        let segments = [
            Segment(start: 0.0, end: 1.0, text: "Start."),
            Segment(start: 65.432, end: 70.0, text: "Mitte."),
            Segment(start: 3661.089, end: 3665.500, text: "Ende.")
        ]

        let srt = SRTFormatter.format(segments: segments)
        #expect(srt.contains("00:00:00,000 --> 00:00:01,000"))
        #expect(srt.contains("00:01:05,432 --> 00:01:10,000"))
        #expect(srt.contains("01:01:01,089 --> 01:01:05,500"))
    }

    @Test("Tier 1 F4.2: SRTFormatter assigns contiguous 1-based cue indices separated by blank lines")
    func testTier1_SRT_SequentialIndexGeneration() {
        let segments = [
            Segment(start: 0.0, end: 1.5, text: "Eins."),
            Segment(start: 2.0, end: 3.5, text: "Zwei."),
            Segment(start: 4.0, end: 5.5, text: "Drei.")
        ]

        let srt = SRTFormatter.format(segments: segments)
        let blocks = srt.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        #expect(blocks.count == 3)
        if blocks.count == 3 {
            #expect(blocks[0].hasPrefix("1\n"))
            #expect(blocks[1].hasPrefix("2\n"))
            #expect(blocks[2].hasPrefix("3\n"))
        }
    }

    @Test("Tier 1 F4.3: Short segment remains on a single subtitle text line")
    func testTier1_SRT_ShortSegmentSingleLine() {
        let segments = [
            Segment(start: 0.0, end: 2.0, text: "Kurzer Text.")
        ]

        let srt = SRTFormatter.format(segments: segments)
        let lines = srt.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")

        #expect(lines.count == 3)
        if lines.count == 3 {
            #expect(lines[0] == "1")
            #expect(lines[1] == "00:00:00,000 --> 00:00:02,000")
            #expect(lines[2] == "Kurzer Text.")
        }
    }

    @Test("Tier 1 F4.4: Text over 42 characters wraps at whitespace boundaries with each line <= 42 chars")
    func testTier1_SRT_LineWrappingUnder42Chars() {
        let longText = "Dies ist ein Test für die Formatierung von langen Zeilen."
        let segments = [
            Segment(start: 0.0, end: 4.0, text: longText)
        ]

        let srt = SRTFormatter.format(segments: segments)
        let lines = srt.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")

        let textLines = Array(lines.dropFirst(2))
        #expect(textLines.count == 2)
        for line in textLines {
            #expect(line.count <= 42, "Line exceeded 42 chars (\(line.count)): \(line)")
        }
        #expect(textLines.joined(separator: " ") == longText)
    }

    @Test("Tier 1 F4.5: Long text respects maximum 2 lines per cue block constraint")
    func testTier1_SRT_MaxTwoLinesConstraint() {
        let veryLongText = "Die Strömungssimulation des Turbinenrades erfordert ein extrem feines und stabiles Gittermodell."
        let segments = [
            Segment(start: 0.0, end: 6.0, text: veryLongText)
        ]

        let srt = SRTFormatter.format(segments: segments)
        let blocks = srt.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        #expect(!blocks.isEmpty)
        for block in blocks {
            let blockLines = block.components(separatedBy: "\n")
            let textLines = Array(blockLines.dropFirst(2))
            #expect(textLines.count >= 1 && textLines.count <= 2, "Each SRT cue must have at most 2 text lines")
            for line in textLines {
                #expect(line.count <= 42, "Line exceeded 42 chars: \(line)")
            }
        }
        let reconstructed = blocks.flatMap { block in
            Array(block.components(separatedBy: "\n").dropFirst(2))
        }.joined(separator: " ")
        #expect(reconstructed == veryLongText, "Long segment must split across cues without dropping words")
    }

    // MARK: - F5: CLI Interface Extensions (5 tests)

    @Test("Tier 1 F5.1: CLI prints version and help usage including M2 flags with exit code 0")
    func testTier1_CLI_VersionAndHelpCommands() throws {
        let versionRes = try E2ETestHelpers.runCLI(["version"])
        #expect(versionRes.exitCode == 0)
        #expect(versionRes.stdout.contains("Transkript Hub"))
        #expect(versionRes.stdout.contains("whisper.cpp"))

        let helpRes = try E2ETestHelpers.runCLI(["--help"])
        #expect(helpRes.exitCode == 0)
        #expect(helpRes.stdout.contains("Usage:"))
        #expect(helpRes.stdout.contains("transcribe"))
        #expect(helpRes.stdout.contains("--no-context"))
        #expect(helpRes.stdout.contains("--prompt"))
        #expect(helpRes.stdout.contains("--srt"))
    }

    @Test("Tier 1 F5.2: CLI supports --no-context flag in transcribe command and help")
    func testTier1_CLI_TranscribeNoContextFlag() throws {
        let helpRes = try E2ETestHelpers.runCLI(["--help"])
        #expect(helpRes.exitCode == 0)
        #expect(helpRes.stdout.contains("--no-context"))

        let missingPath = "/tmp/cli_nocontext_\(UUID().uuidString).m4a"
        let res = try E2ETestHelpers.runCLI(["transcribe", missingPath, "--no-context", "--model", "large-v3-turbo"])
        #expect(res.exitCode == 0 || !res.combinedOutput.isEmpty)
        #expect(!res.combinedOutput.localizedCaseInsensitiveContains("Unknown option"))
        #expect(res.combinedOutput.contains("Input File: \(missingPath)"))
    }

    @Test("Tier 1 F5.3: CLI supports --prompt flag with technical domain terms")
    func testTier1_CLI_TranscribePromptFlag() throws {
        let helpRes = try E2ETestHelpers.runCLI(["--help"])
        #expect(helpRes.exitCode == 0)
        #expect(helpRes.stdout.contains("--prompt"))

        let missingPath = "/tmp/cli_prompt_\(UUID().uuidString).m4a"
        let res = try E2ETestHelpers.runCLI([
            "transcribe", missingPath, "--prompt", "CAD, Motor, Mesh", "--model", "large-v3-turbo"
        ])
        #expect(!res.combinedOutput.localizedCaseInsensitiveContains("Unknown option"))
        #expect(res.combinedOutput.contains("Input File: \(missingPath)"))
    }

    @Test("Tier 1 F5.4: CLI supports --srt subtitle export flag")
    func testTier1_CLI_TranscribeSRTFlag() throws {
        let helpRes = try E2ETestHelpers.runCLI(["--help"])
        #expect(helpRes.exitCode == 0)
        #expect(helpRes.stdout.contains("--srt"))

        let missingPath = "/tmp/cli_srt_\(UUID().uuidString).m4a"
        let res = try E2ETestHelpers.runCLI(["transcribe", missingPath, "--srt", "--model", "large-v3-turbo"])
        #expect(!res.combinedOutput.localizedCaseInsensitiveContains("Unknown option"))
        #expect(res.combinedOutput.contains("Input File: \(missingPath)"))
    }

    @Test("Tier 1 F5.5: CLI resolves --model large-v3-turbo correctly")
    func testTier1_CLI_TranscribeModelSelection() throws {
        #expect(WhisperModel(rawValue: "large-v3-turbo") == .largeV3Turbo)

        let missingPath = "/tmp/cli_model_\(UUID().uuidString).m4a"
        let res = try E2ETestHelpers.runCLI(["transcribe", missingPath, "--model", "large-v3-turbo"])
        #expect(res.stdout.contains("Model: large-v3-turbo"))
    }
}
