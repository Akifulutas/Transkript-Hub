import Foundation
import Testing
import whisper
@testable import TranskriptHubCore

@Suite("E2E Tier 3: Pairwise Combinations")
struct E2EPairwiseTests {

    @Test("Tier 3.1: AudioVAD combined with WhisperCppEngine parameter wiring")
    func testTier3_Pipeline_VADWithParameterWiring() {
        let audio =
            E2ETestHelpers.makeSilence(seconds: 2.0) +
            E2ETestHelpers.makeSineWave(seconds: 2.0, targetRMS: 0.35) +
            E2ETestHelpers.makeSilence(seconds: 2.0)

        let speechSegments = AudioVAD.detectSpeech(samples: audio, sampleRate: E2ETestHelpers.defaultSampleRate)
        #expect(speechSegments.count == 1)

        let options = TranscriptionOptions(
            language: "de",
            useVAD: true,
            initialPrompt: "Turbinenrad, Gittermodell",
            noContext: true,
            suppressBlank: true,
            suppressNonSpeech: true,
            noSpeechThreshold: 0.60
        )
        WhisperCppEngine.withWhisperParams(options: options) { wparams in
            #expect(wparams.no_context == true)
            #expect(wparams.suppress_blank == true)
            #expect(wparams.suppress_nst == true)
            #expect(abs(wparams.no_speech_thold - 0.60) < 0.001)
            #expect(wparams.carry_initial_prompt == true)
            if let langPtr = wparams.language {
                #expect(String(cString: langPtr) == "de")
            } else {
                Issue.record("Expected explicit 'de' language pointer")
            }
        }
    }

    @Test("Tier 3.2: AudioVAD silence filtering paired with TranscriptPostProcessor sanitization")
    func testTier3_Pipeline_VADWithPostProcessor() {
        let audio =
            E2ETestHelpers.makeSilence(seconds: 1.5) +
            E2ETestHelpers.makeSineWave(seconds: 2.0, targetRMS: 0.40) +
            E2ETestHelpers.makeSilence(seconds: 1.5)

        let speechRegions = AudioVAD.detectSpeech(samples: audio, sampleRate: E2ETestHelpers.defaultSampleRate)
        #expect(speechRegions.count == 1)

        let rawSegments = [
            Segment(start: 0.2, end: 1.0, text: "Es heilt die göttliche Kraft."),
            Segment(start: 1.6, end: 3.4, text: "Die Schaufelgeometrie wird vernetzt."),
            Segment(start: 3.8, end: 4.8, text: "Vielen Dank für Ihre Aufmerksamkeit.")
        ]

        let processor = TranscriptPostProcessor()
        let cleanSegments = processor.processSegments(segments: rawSegments, options: PostProcessorOptions())

        #expect(cleanSegments.count == 1)
        if let surviving = cleanSegments.first {
            #expect(surviving.text == "Die Schaufelgeometrie wird vernetzt.")
            #expect(surviving.start == 1.6)
            #expect(surviving.end == 3.4)
        }
    }

    @Test("Tier 3.3: TranscriptPostProcessor pruned segments paired with SRTFormatter")
    func testTier3_Pipeline_PostProcessorWithSRTFormatter() {
        let rawSegments = [
            Segment(start: 0.5, end: 3.0, text: "Wir prüfen zuerst das Gittermodell."),
            Segment(start: 3.5, end: 5.5, text: "Es heilt die göttliche Kraft."),
            Segment(start: 6.0, end: 8.5, text: "Vielen Dank fürs Zuschauen."),
            Segment(start: 9.0, end: 12.0, text: "Danach startet die Netzgenerierung.")
        ]

        let processor = TranscriptPostProcessor()
        let cleaned = processor.processSegments(segments: rawSegments, options: PostProcessorOptions())
        let srt = SRTFormatter.format(segments: cleaned)

        #expect(!srt.contains("göttliche Kraft"))
        #expect(!srt.contains("Vielen Dank"))
        #expect(srt.contains("1\n00:00:00,500 --> 00:00:03,000\nWir prüfen zuerst das Gittermodell."))
        #expect(srt.contains("2\n00:00:09,000 --> 00:00:12,000\nDanach startet die Netzgenerierung."))
    }

    @Test("Tier 3.4: End-to-end synthetic audio -> VAD -> Engine -> PostProcessor -> SRT -> OutputWriter")
    func testTier3_Pipeline_EndToEndSyntheticAudioToSRT() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("E2E_Tier3_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let samples =
            E2ETestHelpers.makeSilence(seconds: 1.5) +
            E2ETestHelpers.makeSineWave(seconds: 2.0, targetRMS: 0.38) +
            E2ETestHelpers.makeSilence(seconds: 1.5) +
            E2ETestHelpers.makeSineWave(seconds: 2.0, targetRMS: 0.38) +
            E2ETestHelpers.makeSilence(seconds: 1.5)
        let prepared = PreparedAudio(samples: samples, duration: Double(samples.count) / 16000.0)

        let detectedRegions = AudioVAD.detectSpeech(samples: prepared.samples, sampleRate: 16000.0)
        #expect(detectedRegions.count == 2)
        if detectedRegions.count == 2 {
            #expect(detectedRegions[0].start <= 1.5 && detectedRegions[0].end >= 3.5)
            #expect(detectedRegions[1].start <= 5.0 && detectedRegions[1].end >= 7.0)
        }

        let mockEngine = MockTranscriptionEngine(segments: [
            Segment(start: 1.5, end: 3.5, text: "Das Turbinenrad zeigt saubere Strömung."),
            Segment(start: 4.0, end: 4.8, text: "Es heilt die göttliche Kraft."),
            Segment(start: 5.0, end: 7.0, text: "Der Zylinderkopf bleibt thermisch stabil.")
        ])

        let options = TranscriptionOptions(language: "de", useVAD: true, initialPrompt: "Turbinenrad, Zylinderkopf", noContext: true)
        let result = try await mockEngine.transcribe(prepared, options: options)

        let captured = await mockEngine.capturedOptions
        #expect(captured.count == 1)
        if let recordedOptions = captured.first {
            #expect(recordedOptions.language == "de")
            #expect(recordedOptions.useVAD == true)
            #expect(recordedOptions.initialPrompt == "Turbinenrad, Zylinderkopf")
            #expect(recordedOptions.noContext == true)
            #expect(recordedOptions.suppressBlank == true)
            #expect(recordedOptions.suppressNonSpeech == true)
        }

        let processor = TranscriptPostProcessor()
        let cleanSegments = processor.processSegments(segments: result.segments, options: PostProcessorOptions())
        let srtContent = SRTFormatter.format(segments: cleanSegments)

        let writer = OutputWriter(customOutputDirectory: tempDir)
        let srtURL = tempDir.appendingPathComponent("synthetic_cad.srt")
        try writer.write(content: srtContent, to: srtURL)

        #expect(FileManager.default.fileExists(atPath: srtURL.path))
        let diskContent = try String(contentsOf: srtURL, encoding: .utf8)
        #expect(diskContent.contains("Turbinenrad"))
        #expect(diskContent.contains("Zylinderkopf"))
        #expect(!diskContent.contains("göttliche Kraft"))
        #expect(diskContent.contains("1\n"))
        #expect(diskContent.contains("2\n"))
    }

    @Test("Tier 3.5: CLI flags configuration paired with TranscriptionOptions and PostProcessor/SRT")
    func testTier3_Pipeline_CLIConfigToPostProcessorWiring() throws {
        let helpRes = try E2ETestHelpers.runCLI(["--help"])
        #expect(helpRes.exitCode == 0)
        #expect(helpRes.stdout.contains("--no-context"))
        #expect(helpRes.stdout.contains("--prompt"))
        #expect(helpRes.stdout.contains("--srt"))

        let options = TranscriptionOptions(
            language: "de",
            initialPrompt: "CAD, Netzgenerierung",
            noContext: true
        )
        WhisperCppEngine.withWhisperParams(options: options) { wparams in
            #expect(wparams.no_context == true)
            #expect(wparams.carry_initial_prompt == true)
        }

        let processor = TranscriptPostProcessor()
        let cleaned = processor.processSegments(segments: [
            Segment(start: 0.0, end: 3.0, text: "Netzgenerierung abgeschlossen.")
        ])
        let srt = SRTFormatter.format(segments: cleaned)
        #expect(srt.contains("Netzgenerierung abgeschlossen."))
    }

    @Test("Tier 3.6: Hallucination suppression across full pipeline under low-SNR noisy audio")
    func testTier3_Pipeline_HallucinationSuppressionUnderNoise() async throws {
        let noise = E2ETestHelpers.makeDeterministicNoise(seconds: 7.0, targetRMS: 0.005)
        let speech = E2ETestHelpers.makeSilence(seconds: 2.0) +
            E2ETestHelpers.makeSineWave(seconds: 2.0, targetRMS: 0.35)
        let audioSamples = E2ETestHelpers.mix(noise, speech)
        let prepared = PreparedAudio(samples: audioSamples, duration: 7.0)

        let regions = AudioVAD.detectSpeech(samples: prepared.samples, sampleRate: 16000.0)
        #expect(regions.count == 1)
        if let region = regions.first {
            #expect(region.start <= 2.0 && region.end >= 4.0)
        }

        let noisyTranscript = [
            Segment(start: 0.2, end: 1.4, text: "Ja. Ja. Ja. Ja. Ja. Ja. Ja. Ja."),
            Segment(start: 2.0, end: 4.0, text: "Die Vernetzung des Kurbelgehäuses läuft."),
            Segment(start: 4.8, end: 6.5, text: "Ich hoffe, es hilft, es heilt die göttliche Kraft!")
        ]
        let mockEngine = MockTranscriptionEngine(segments: noisyTranscript)
        let result = try await mockEngine.transcribe(
            prepared,
            options: TranscriptionOptions(language: "de", noContext: true)
        )

        let captured = await mockEngine.capturedOptions
        #expect(captured.count == 1)
        if let recordedOptions = captured.first {
            #expect(recordedOptions.language == "de")
            #expect(recordedOptions.noContext == true)
            #expect(recordedOptions.useVAD == true)
            #expect(recordedOptions.suppressBlank == true)
            #expect(recordedOptions.suppressNonSpeech == true)
            #expect(abs(recordedOptions.noSpeechThreshold - 0.60) < 0.001)
        }

        let processor = TranscriptPostProcessor()
        let cleanSegments = processor.processSegments(segments: result.segments)
        let srt = SRTFormatter.format(segments: cleanSegments)

        #expect(!srt.contains("göttliche Kraft"))
        #expect(srt.contains("Kurbelgehäuses"))
        let jaCount = srt.components(separatedBy: "Ja").count - 1
        #expect(jaCount <= 2)
    }
}
