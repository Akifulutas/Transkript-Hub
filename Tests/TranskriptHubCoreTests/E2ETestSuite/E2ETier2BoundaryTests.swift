import Foundation
import Testing
import whisper
@testable import TranskriptHubCore

@Suite("E2E Tier 2: Boundary & Corner Cases")
struct E2EBoundaryTests {

    // MARK: - F1: AudioVAD Boundaries (5 tests)

    @Test("Tier 2 F1.1: VAD handles empty sample array safely")
    func testTier2_VAD_EmptySamples() {
        let segments = AudioVAD.detectSpeech(samples: [], sampleRate: E2ETestHelpers.defaultSampleRate)
        #expect(segments.isEmpty)
    }

    @Test("Tier 2 F1.2: VAD returns empty for sub-frame audio (<1ms)")
    func testTier2_VAD_SubFrameAudio() {
        let subFrame = [Float](repeating: 0.5, count: 10)
        let segments = AudioVAD.detectSpeech(samples: subFrame, sampleRate: E2ETestHelpers.defaultSampleRate)
        #expect(segments.isEmpty)
    }

    @Test("Tier 2 F1.3: VAD clamps pre-padding at buffer start to >= 0.0s")
    func testTier2_VAD_BoundaryPaddingAtStartClamped() {
        let audio =
            E2ETestHelpers.makeSilence(seconds: 0.05) +
            E2ETestHelpers.makeSineWave(seconds: 1.0, targetRMS: 0.35) +
            E2ETestHelpers.makeSilence(seconds: 1.5)

        let segments = AudioVAD.detectSpeech(samples: audio, sampleRate: E2ETestHelpers.defaultSampleRate)
        #expect(segments.count == 1)
        if let seg = segments.first {
            #expect(seg.start >= 0.0, "Start timestamp must clamp at 0.0s, never negative")
            #expect(seg.start <= 0.055)
        }
    }

    @Test("Tier 2 F1.4: VAD clamps post-padding at buffer end to <= total duration T")
    func testTier2_VAD_BoundaryPaddingAtEndClamped() {
        let totalDuration = 2.6
        let audio =
            E2ETestHelpers.makeSilence(seconds: 1.5) +
            E2ETestHelpers.makeSineWave(seconds: 1.0, targetRMS: 0.35) +
            E2ETestHelpers.makeSilence(seconds: 0.1)

        let segments = AudioVAD.detectSpeech(samples: audio, sampleRate: E2ETestHelpers.defaultSampleRate)
        #expect(segments.count == 1)
        if let seg = segments.first {
            #expect(seg.end <= totalDuration + 0.001, "End timestamp must clamp to total duration \(totalDuration)s")
            #expect(seg.end >= 2.49)
        }
    }

    @Test("Tier 2 F1.5: VAD handles continuous speech signal with zero silence")
    func testTier2_VAD_ContinuousSignalZeroSilence() {
        let audio = E2ETestHelpers.makeSineWave(seconds: 10.0, targetRMS: 0.35)

        let segments = AudioVAD.detectSpeech(samples: audio, sampleRate: E2ETestHelpers.defaultSampleRate)
        #expect(segments.count == 1)
        if let seg = segments.first {
            #expect(seg.start <= 0.05)
            #expect(seg.end >= 9.95 && seg.end <= 10.001)
        }
    }

    // MARK: - F2: WhisperCppEngine Parameter Wiring Boundaries (5 tests)

    @Test("Tier 2 F2.1: Non-positive thread counts are clamped to >= 1")
    func testTier2_Options_ThreadClamping() {
        let zeroThreads = TranscriptionOptions(threads: 0)
        let negativeThreads = TranscriptionOptions(threads: -4)

        #expect(zeroThreads.threads == 1)
        #expect(negativeThreads.threads == 1)

        WhisperCppEngine.withWhisperParams(options: zeroThreads) { wparamsZero in
            #expect(wparamsZero.n_threads == 1)
        }
        WhisperCppEngine.withWhisperParams(options: negativeThreads) { wparamsNeg in
            #expect(wparamsNeg.n_threads == 1)
        }
    }

    @Test("Tier 2 F2.2: Boundary noSpeechThreshold values 0.0 and 1.0 map without distortion")
    func testTier2_Options_ThresholdBoundaryLimits() {
        let optMin = TranscriptionOptions(noSpeechThreshold: 0.0)
        let optMax = TranscriptionOptions(noSpeechThreshold: 1.0)

        #expect(optMin.noSpeechThreshold == 0.0)
        #expect(optMax.noSpeechThreshold == 1.0)

        WhisperCppEngine.withWhisperParams(options: optMin) { wparamsMin in
            #expect(abs(wparamsMin.no_speech_thold - 0.0) < 0.0001)
        }
        WhisperCppEngine.withWhisperParams(options: optMax) { wparamsMax in
            #expect(abs(wparamsMax.no_speech_thold - 1.0) < 0.0001)
        }
    }

    @Test("Tier 2 F2.3: Whitespace-only initialPrompt is treated as empty/nil in C parameters")
    func testTier2_Options_WhitespaceOnlyPrompt() {
        let options = TranscriptionOptions(initialPrompt: "   \n\t  ")
        WhisperCppEngine.withWhisperParams(options: options) { wparams in
            #expect(wparams.initial_prompt == nil, "Whitespace-only prompt must not be passed as C string")
            #expect(wparams.carry_initial_prompt == false)
        }
    }

    @Test("Tier 2 F2.4: Auto vs explicit language mapping sets wparams.language accurately")
    func testTier2_Options_LanguageAutoVsExplicit() {
        let autoOpt = TranscriptionOptions(language: "auto")
        let emptyOpt = TranscriptionOptions(language: "")
        let germanOpt = TranscriptionOptions(language: "de")

        WhisperCppEngine.withWhisperParams(options: autoOpt) { wAuto in
            #expect(wAuto.language == nil)
        }
        WhisperCppEngine.withWhisperParams(options: emptyOpt) { wEmpty in
            #expect(wEmpty.language == nil)
        }
        WhisperCppEngine.withWhisperParams(options: germanOpt) { wGerman in
            #expect(wGerman.language != nil)
            if let ptr = wGerman.language {
                #expect(String(cString: ptr) == "de")
            }
        }
    }

    @Test("Tier 2 F2.5: Concurrent cancellation token reads and writes are race-free")
    func testTier2_Engine_RapidConcurrentCancellation() async {
        let token = TranscriptionCancellationToken()

        await withTaskGroup(of: Bool.self) { group in
            for idx in 0..<24 {
                group.addTask {
                    if idx % 3 == 0 {
                        token.cancel()
                    }
                    return token.isCancelled
                }
            }
            for await _ in group {}
        }

        #expect(token.isCancelled == true)
    }

    // MARK: - F3: TranscriptPostProcessor Boundaries (5 tests)

    @Test("Tier 2 F3.1: Single word excessive repetition is collapsed to <= 2 occurrences")
    func testTier2_PostProcessor_SingleWordExcessiveRepetition() {
        let processor = TranscriptPostProcessor()
        let text = "Ja. Ja. Ja. Ja. Ja. Ja. Ja. Ja. Ja."

        let deduplicated = processor.deduplicatePhrases(text)
        let jaCount = deduplicated.components(separatedBy: "Ja").count - 1
        #expect(jaCount >= 1 && jaCount <= 2, "Expected <= 2 'Ja' occurrences, got \(jaCount): \(deduplicated)")

        let processedSegments = processor.processSegments(
            segments: [Segment(start: 0.0, end: 4.0, text: text)],
            options: PostProcessorOptions()
        )
        #expect(processedSegments.count == 1)
        if let seg = processedSegments.first {
            let segJaCount = seg.text.components(separatedBy: "Ja").count - 1
            #expect(segJaCount >= 1 && segJaCount <= 2)
        }
    }

    @Test("Tier 2 F3.2: Input containing only hallucinated segments yields empty result")
    func testTier2_PostProcessor_AllSegmentsHallucinations() {
        let processor = TranscriptPostProcessor()
        let segments = [
            Segment(start: 0.0, end: 2.0, text: "Es heilt die göttliche Kraft."),
            Segment(start: 2.5, end: 5.0, text: "Vielen Dank für Ihre Aufmerksamkeit."),
            Segment(start: 5.5, end: 8.0, text: "Subtitles by the Amara.org community")
        ]

        let processedSegments = processor.processSegments(segments: segments, options: PostProcessorOptions())
        let processedText = processor.process(segments: segments, options: PostProcessorOptions())

        #expect(processedSegments.isEmpty)
        #expect(processedText.isEmpty)
    }

    @Test("Tier 2 F3.3: Alternating non-boilerplate ping-pong repetition loop is pruned")
    func testTier2_PostProcessor_AlternatingHallucinationPingPong() {
        let processor = TranscriptPostProcessor()
        let segments = [
            Segment(start: 0.0, end: 1.0, text: "CAD-Modellierung."),
            Segment(start: 1.5, end: 2.5, text: "Netzgenerierung."),
            Segment(start: 3.0, end: 4.0, text: "CAD-Modellierung."),
            Segment(start: 4.5, end: 5.5, text: "Netzgenerierung.")
        ]

        // Control check: verify non-boilerplate phrases are not stripped by boilerplate filtering alone
        let unpruned = processor.processSegments(
            segments: segments,
            options: PostProcessorOptions(deduplicateRepetitions: false)
        )
        #expect(unpruned.count == 4, "Non-boilerplate phrases must bypass standalone boilerplate stripping")

        let processedSegments = processor.processSegments(segments: segments, options: PostProcessorOptions())
        let processedText = processor.process(segments: segments, options: PostProcessorOptions())

        #expect(processedSegments.count < segments.count, "Alternating ping-pong loop must be pruned")
        #expect(processedSegments.count == 3, "Expected 3 segments after ping-pong loop suppression, got \(processedSegments.count)")
        #expect(processedText.contains("CAD-Modellierung."))
        #expect(processedText.contains("Netzgenerierung."))
        let netzCount = processedText.components(separatedBy: "Netzgenerierung.").count - 1
        let cadCount = processedText.components(separatedBy: "CAD-Modellierung.").count - 1
        #expect(netzCount == 1, "Alternating 'Netzgenerierung.' repetition must be pruned by ping-pong check, got \(netzCount)")
        #expect(cadCount == 2, "Expected 2 'CAD-Modellierung.' occurrences, got \(cadCount)")
    }

    @Test("Tier 2 F3.4: Empty and whitespace-only segments are dropped safely")
    func testTier2_PostProcessor_ZeroLengthSegmentText() {
        let processor = TranscriptPostProcessor()
        let segments = [
            Segment(start: 0.0, end: 1.0, text: ""),
            Segment(start: 1.0, end: 2.0, text: "   \n\t  "),
            Segment(start: 2.0, end: 4.0, text: "Gültiger technischer Satz."),
            Segment(start: 4.0, end: 5.0, text: " ")
        ]

        let processed = processor.processSegments(segments: segments, options: PostProcessorOptions())
        #expect(processed.count == 1)
        if let first = processed.first {
            #expect(first.text == "Gültiger technischer Satz.")
            #expect(first.start == 2.0)
            #expect(first.end == 4.0)
        }
    }

    @Test("Tier 2 F3.5: Punctuation and uppercase variants of hallucinations are pruned")
    func testTier2_PostProcessor_PunctuationAndCaseInsensitiveMatching() {
        let processor = TranscriptPostProcessor()
        let segments = [
            Segment(start: 0.0, end: 3.0, text: "...ES HEILT DIE GÖTTLICHE KRAFT!!!")
        ]

        let processedSegments = processor.processSegments(segments: segments, options: PostProcessorOptions())
        let processedText = processor.process(segments: segments, options: PostProcessorOptions())

        #expect(processedSegments.isEmpty)
        #expect(processedText.isEmpty)
    }

    // MARK: - F4: SRTFormatter Boundaries (5 tests)

    @Test("Tier 2 F4.1: Single unbroken German compound word >42 chars wraps to <=42 chars without truncation")
    func testTier2_SRT_SingleWordExceeding42Chars() {
        let compound = "Rindfleischetikettierungsüberwachungsaufgabenübertragungsgesetz"
        #expect(compound.count > 42)
        let segments = [
            Segment(start: 0.0, end: 5.0, text: compound)
        ]

        let srt = SRTFormatter.format(segments: segments)
        let blocks = srt.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        #expect(blocks.count == 1)
        if let block = blocks.first {
            let blockLines = block.components(separatedBy: "\n")
            #expect(blockLines.first == "1")
            #expect(blockLines.dropFirst().first == "00:00:00,000 --> 00:00:05,000")
            let textLines = Array(blockLines.dropFirst(2))
            #expect(textLines.count >= 1 && textLines.count <= 2, "Expected <= 2 lines per cue, got \(textLines.count)")
            for line in textLines {
                #expect(line.count <= 42, "SRT line exceeded 42 chars (\(line.count)): \(line)")
            }
            #expect(textLines.joined() == compound, "Oversized German compound word must be preserved without loss")
        }
    }

    @Test("Tier 2 F4.2: Zero-duration segment enforces positive minimum display interval (>=0.1s)")
    func testTier2_SRT_ZeroDurationSegment() {
        let segments = [
            Segment(start: 2.500, end: 2.500, text: "Klick.")
        ]

        let srt = SRTFormatter.format(segments: segments)
        #expect(srt.contains("00:00:02,500 --> 00:00:02,600"), "Zero-duration SRT cue must clamp to minimum 0.1s display interval")
        #expect(!srt.contains("00:00:02,500 --> 00:00:02,500"))
        #expect(srt.contains("Klick."))
    }

    @Test("Tier 2 F4.3: Empty segments array formats to empty string")
    func testTier2_SRT_EmptySegmentsArray() {
        let srt = SRTFormatter.format(segments: [])
        #expect(srt.isEmpty)
    }

    @Test("Tier 2 F4.4: Empty text segments are omitted while preserving contiguous cue indices")
    func testTier2_SRT_SegmentsWithEmptyText() {
        let segments = [
            Segment(start: 0.0, end: 1.0, text: "Eins."),
            Segment(start: 1.0, end: 2.0, text: ""),
            Segment(start: 2.0, end: 3.0, text: "   \n "),
            Segment(start: 3.0, end: 4.0, text: "Zwei.")
        ]

        let srt = SRTFormatter.format(segments: segments)
        let blocks = srt.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        #expect(blocks.count == 2)
        if blocks.count == 2 {
            #expect(blocks[0].hasPrefix("1\n"))
            #expect(blocks[0].contains("Eins."))
            #expect(blocks[1].hasPrefix("2\n"))
            #expect(blocks[1].contains("Zwei."))
        }
    }

    @Test("Tier 2 F4.5: High timestamps >= 100 hours format without truncation or overflow")
    func testTier2_SRT_HighTimestampHourRollover() {
        let segments = [
            Segment(start: 360_000.0, end: 360_005.250, text: "Langzeittest.")
        ]

        let srt = SRTFormatter.format(segments: segments)
        #expect(srt.contains("100:00:00,000 --> 100:00:05,250"))
    }

    // MARK: - F5: CLI Interface Boundaries (5 tests)

    @Test("Tier 2 F5.1: CLI reports missing option argument cleanly instead of ignoring flag")
    func testTier2_CLI_MissingOptionArgument() throws {
        let missingPath = "/tmp/cli_missing_arg_\(UUID().uuidString).m4a"
        let res = try E2ETestHelpers.runCLI(["transcribe", missingPath, "--model"])

        #expect(res.combinedOutput.contains("--model") || res.combinedOutput.localizedCaseInsensitiveContains("missing"))
        #expect(!res.stdout.contains("Model: tiny"), "Missing --model value must not silently fall back to tiny")
    }

    @Test("Tier 2 F5.2: CLI reports invalid model name cleanly")
    func testTier2_CLI_InvalidModelName() throws {
        let missingPath = "/tmp/cli_bad_model_\(UUID().uuidString).m4a"
        let res = try E2ETestHelpers.runCLI(["transcribe", missingPath, "--model", "nonexistent-model"])

        #expect(res.combinedOutput.contains("Invalid model: nonexistent-model"))
    }

    @Test("Tier 2 F5.3: CLI rejects unknown flags with an explicit error diagnostic")
    func testTier2_CLI_UnknownFlags() throws {
        let missingPath = "/tmp/cli_flagcheck_\(UUID().uuidString).m4a"
        let res = try E2ETestHelpers.runCLI(["transcribe", missingPath, "--invalid-flag-xyz"])

        #expect(!res.combinedOutput.isEmpty)
        #expect(
            res.combinedOutput.localizedCaseInsensitiveContains("unknown") ||
            res.combinedOutput.localizedCaseInsensitiveContains("invalid") ||
            res.combinedOutput.localizedCaseInsensitiveContains("unsupported") ||
            res.combinedOutput.localizedCaseInsensitiveContains("unrecognized") ||
            res.combinedOutput.contains("--invalid-flag-xyz")
        )
        #expect(
            !res.combinedOutput.contains("Audio decode error:"),
            "Unknown flag --invalid-flag-xyz must be rejected before attempting audio decode"
        )
    }

    @Test("Tier 2 F5.4: CLI reports non-existent audio file cleanly without unhandled crash")
    func testTier2_CLI_NonExistentAudioFile() throws {
        let missingPath = "/tmp/does_not_exist_\(UUID().uuidString).m4a"
        let res = try E2ETestHelpers.runCLI(["transcribe", missingPath, "--model", "large-v3-turbo"])

        #expect(res.combinedOutput.localizedCaseInsensitiveContains("error") || res.combinedOutput.contains("bulunamadı"))
    }

    @Test("Tier 2 F5.5: CLI parses flags before or after positional audio path identically")
    func testTier2_CLI_FlagOrderIndependence() throws {
        let missingPath = "/tmp/cli_order_\(UUID().uuidString).m4a"
        let resFlagsFirst = try E2ETestHelpers.runCLI([
            "transcribe", "--srt", "--no-context", "--lang", "de", "--model", "large-v3-turbo", missingPath
        ])
        let resFileFirst = try E2ETestHelpers.runCLI([
            "transcribe", missingPath, "--srt", "--no-context", "--lang", "de", "--model", "large-v3-turbo"
        ])

        #expect(resFlagsFirst.stdout.contains("Input File: \(missingPath)"))
        #expect(resFileFirst.stdout.contains("Input File: \(missingPath)"))
        #expect(resFlagsFirst.stdout.contains("Model: large-v3-turbo"))
        #expect(resFileFirst.stdout.contains("Model: large-v3-turbo"))
    }
}
