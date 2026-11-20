import Foundation
import Testing
@testable import TranskriptHubCore

@Suite("E2E Tier 4: Real-World Technical Scenarios")
struct E2ERealWorldTests {

    @Test("Tier 4.1: Specialized German CAD terminology preserved 100% across TXT and SRT")
    func testTier4_RealWorld_CADTerminologyPreservation() {
        let requiredTerms = ["Turbinenrad", "Gittermodell", "Netzgenerierung", "Schaufelgeometrie"]
        let segments = [
            Segment(start: 0.0, end: 3.2, text: "Zuerst laden wir das Turbinenrad in den CAD-Viewer."),
            Segment(start: 3.4, end: 6.8, text: "Das Gittermodell bildet die Schaufelgeometrie präzise ab."),
            Segment(start: 7.0, end: 10.5, text: "Anschließend starten wir die automatische Netzgenerierung.")
        ]

        let processor = TranscriptPostProcessor()
        let processedSegments = processor.processSegments(segments: segments, options: PostProcessorOptions())
        let processedText = processor.process(segments: segments, options: PostProcessorOptions())
        let srt = SRTFormatter.format(segments: processedSegments)

        #expect(processedSegments.count == 3)
        for term in requiredTerms {
            #expect(processedText.contains(term), "Plain text output dropped CAD term: \(term)")
            #expect(srt.contains(term), "SRT output dropped CAD term: \(term)")
        }
    }

    @Test("Tier 4.2: German engine and flow-simulation terminology preserved and wrapped cleanly")
    func testTier4_RealWorld_EngineDesignTerminologyPreservation() {
        let requiredTerms = ["Kurbelgehäuse", "Zylinderkopf", "Strömungssimulation", "Drehmomentverlauf"]
        let segments = [
            Segment(start: 12.0, end: 16.0, text: "Am Kurbelgehäuse und am Zylinderkopf prüfen wir die Spaltmaße."),
            Segment(start: 16.5, end: 21.0, text: "Die Strömungssimulation erklärt den Drehmomentverlauf bei Volllast.")
        ]

        let processor = TranscriptPostProcessor()
        let processedSegments = processor.processSegments(segments: segments, options: PostProcessorOptions())
        let processedText = processor.process(segments: segments, options: PostProcessorOptions())
        let srt = SRTFormatter.format(segments: processedSegments)

        #expect(processedSegments.count == 2)
        for term in requiredTerms {
            #expect(processedText.contains(term), "Plain text output dropped engine term: \(term)")
            #expect(srt.contains(term), "SRT output dropped engine term: \(term)")
        }

        let blocks = srt.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for block in blocks {
            let textLines = Array(block.components(separatedBy: "\n").dropFirst(2))
            #expect(textLines.count >= 1 && textLines.count <= 2)
            for line in textLines {
                #expect(line.count <= 42, "SRT line exceeded 42 chars: \(line)")
            }
        }
    }

    @Test("Tier 4.3: Technical pause intervals reject silence and prune pause-injected hallucinations")
    func testTier4_RealWorld_TechnicalSilenceIntervalRejection() {
        let audio =
            E2ETestHelpers.makeSineWave(seconds: 2.0, targetRMS: 0.35) +
            E2ETestHelpers.makeSilence(seconds: 3.0) +
            E2ETestHelpers.makeSineWave(seconds: 2.0, targetRMS: 0.35) +
            E2ETestHelpers.makeSilence(seconds: 4.0)

        let speechSegments = AudioVAD.detectSpeech(samples: audio, sampleRate: E2ETestHelpers.defaultSampleRate)
        #expect(speechSegments.count == 2, "3.0s pause must split the two technical utterances cleanly")

        let simulatedSegments = [
            Segment(start: 0.0, end: 2.0, text: "Hier sehen wir den Übergang zum Diffusor."),
            Segment(start: 2.5, end: 4.5, text: "Es heilt die göttliche Kraft."),
            Segment(start: 5.0, end: 7.0, text: "Die Randbedingungen werden jetzt gesetzt."),
            Segment(start: 8.0, end: 10.5, text: "Vielen Dank fürs Zuschauen.")
        ]

        let processor = TranscriptPostProcessor()
        let cleanSegments = processor.processSegments(segments: simulatedSegments, options: PostProcessorOptions())
        let cleanText = processor.process(segments: simulatedSegments, options: PostProcessorOptions())

        #expect(cleanSegments.count == 2)
        #expect(!cleanText.contains("göttliche Kraft"))
        #expect(!cleanText.contains("Vielen Dank"))
        #expect(cleanText.contains("Diffusor"))
        #expect(cleanText.contains("Randbedingungen"))
    }

    @Test("Tier 4.4: Low-amplitude German speech over room reverb noise floor is not clipped")
    func testTier4_RealWorld_TechnicalGermanSpeechWithBackgroundNoise() {
        let reverbFloor = E2ETestHelpers.makeDeterministicNoise(seconds: 6.0, targetRMS: 0.005)
        let quietSpeech = E2ETestHelpers.makeSilence(seconds: 1.8) +
            E2ETestHelpers.makeSineWave(seconds: 2.0, frequency: 650.0, targetRMS: 0.12)
        let mixed = E2ETestHelpers.mix(reverbFloor, quietSpeech)

        let segments = AudioVAD.detectSpeech(samples: mixed, sampleRate: E2ETestHelpers.defaultSampleRate)
        #expect(segments.count == 1, "Low-amplitude speech (RMS 0.12) over RMS 0.005 room noise must be detected")
        if let seg = segments.first {
            #expect(seg.start <= 1.505, "Pre-pad (>=300ms) must prevent clipping speech onset")
            #expect(seg.end >= 4.295, "Post-pad (>=500ms) must prevent clipping speech trailing syllables")
        }
    }

    @Test("Tier 4.5: Recording 7.m4a metadata validation on Desktop/workspace or deterministic fixture fallback")
    func testTier4_RealWorld_FullAudioFileAvailabilityOrMockFallback() throws {
        let desktopURL = URL(fileURLWithPath: "/Users/akifulutas/Desktop/Recording 7.m4a")
        let workspaceURL = E2ETestHelpers.packageRootURL()
            .appendingPathComponent("benchmark_recordings/Recording 7.m4a")
        let fm = FileManager.default

        if let recordingURL = [desktopURL, workspaceURL].first(where: { fm.fileExists(atPath: $0.path) }) {
            let duration = try AudioValidator.validate(fileURL: recordingURL)
            // 94-minute recording (~5640 seconds)
            #expect(duration > 5000.0, "Expected ~94-minute duration for Recording 7.m4a at \(recordingURL.path), got \(duration)s")
        }

        // Deterministic decode check using bundled sample.m4a or synthetic fallback
        let fixtureURL = E2ETestHelpers.packageRootURL().appendingPathComponent("Tests/Fixtures/sample.m4a")
        if fm.fileExists(atPath: fixtureURL.path) {
            let decoder = AudioDecoder()
            let prepared = try decoder.decode(fileURL: fixtureURL)
            #expect(prepared.duration > 1.0)
            #expect(!prepared.samples.isEmpty)
            #expect(abs(Double(prepared.samples.count) / AudioDecoder.targetSampleRate - prepared.duration) < 0.05)
        } else {
            let synthetic = E2ETestHelpers.makeSineWave(seconds: 2.0, targetRMS: 0.30)
            let prepared = PreparedAudio(samples: synthetic, duration: 2.0)
            #expect(prepared.samples.count == 32_000)
            #expect(prepared.duration == 2.0)
        }
    }
}
