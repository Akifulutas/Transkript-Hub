import Foundation
import Testing
import whisper
@testable import TranskriptHubCore

@Suite("WhisperCppEngine Parameter Wiring & Boundaries Test Suite")
struct WhisperCppEngineTests {

    @Test("TranscriptionOptions default values enforce anti-hallucination settings")
    func testTranscriptionOptionsDefaults() {
        let options = TranscriptionOptions()

        #expect(options.language == nil)
        #expect(options.useVAD == true)
        #expect(options.threads >= 1)
        #expect(options.initialPrompt == nil)
        #expect(options.tokenTimestamps == true)
        #expect(options.noContext == true)
        #expect(options.suppressBlank == true)
        #expect(options.suppressNonSpeech == true)
        #expect(options.noSpeechThreshold == 0.60)
        #expect(options.entropyThreshold == 2.4)
        #expect(options.temperature == 0.0)
        #expect(options.temperatureInc == 0.2)
    }

    @Test("TranscriptionOptions clamps non-positive thread counts to >= 1")
    func testThreadCountClamping() {
        let zeroThreads = TranscriptionOptions(threads: 0)
        let negativeThreads = TranscriptionOptions(threads: -8)

        #expect(zeroThreads.threads == 1)
        #expect(negativeThreads.threads == 1)
    }

    @Test("withWhisperParams maps all anti-hallucination options 1:1 to whisper_full_params")
    func testWhisperParamsWiring() {
        let options = TranscriptionOptions(
            language: "de",
            useVAD: true,
            threads: 4,
            initialPrompt: "Turbinenrad, Gittermodell, Netzgenerierung",
            tokenTimestamps: false,
            noContext: false,
            suppressBlank: false,
            suppressNonSpeech: false,
            noSpeechThreshold: 0.75,
            entropyThreshold: 2.8,
            temperature: 0.4,
            temperatureInc: 0.1
        )

        WhisperCppEngine.withWhisperParams(options: options) { wparams in
            #expect(wparams.n_threads == 4)
            #expect(wparams.token_timestamps == false)
            #expect(wparams.no_context == false)
            #expect(wparams.suppress_blank == false)
            #expect(wparams.suppress_nst == false)
            #expect(abs(wparams.no_speech_thold - 0.75) < 0.0001)
            #expect(abs(wparams.entropy_thold - 2.8) < 0.0001)
            #expect(abs(wparams.temperature - 0.4) < 0.0001)
            #expect(abs(wparams.temperature_inc - 0.1) < 0.0001)
            #expect(wparams.carry_initial_prompt == true)

            let langStr = wparams.language.map { String(cString: $0) }
            let promptStr = wparams.initial_prompt.map { String(cString: $0) }
            #expect(langStr == "de")
            #expect(promptStr == "Turbinenrad, Gittermodell, Netzgenerierung")
        }
    }

    @Test("Boundary threshold limits (0.0 and 1.0) map without distortion")
    func testThresholdBoundaryLimits() {
        let zeroThresh = TranscriptionOptions(noSpeechThreshold: 0.0, entropyThreshold: 0.0, temperature: 0.0, temperatureInc: 0.0)
        WhisperCppEngine.withWhisperParams(options: zeroThresh) { wparams in
            #expect(wparams.no_speech_thold == 0.0)
            #expect(wparams.entropy_thold == 0.0)
            #expect(wparams.temperature == 0.0)
            #expect(wparams.temperature_inc == 0.0)
        }

        let oneThresh = TranscriptionOptions(noSpeechThreshold: 1.0, entropyThreshold: 5.0, temperature: 1.0, temperatureInc: 0.5)
        WhisperCppEngine.withWhisperParams(options: oneThresh) { wparams in
            #expect(wparams.no_speech_thold == 1.0)
            #expect(wparams.entropy_thold == 5.0)
            #expect(wparams.temperature == 1.0)
            #expect(wparams.temperature_inc == 0.5)
        }
    }

    @Test("Whitespace-only, empty, and nil prompts disable carry_initial_prompt and set initial_prompt to nil")
    func testPromptNormalization() {
        for rawPrompt in [nil, "", "   ", "\n\t  \r\n"] {
            let options = TranscriptionOptions(initialPrompt: rawPrompt)
            WhisperCppEngine.withWhisperParams(options: options) { wparams in
                #expect(wparams.initial_prompt == nil)
                #expect(wparams.carry_initial_prompt == false)
            }
        }

        let paddedPrompt = TranscriptionOptions(initialPrompt: "  Schaufelgeometrie, Kurbelgehäuse \n")
        WhisperCppEngine.withWhisperParams(options: paddedPrompt) { wparams in
            #expect(wparams.carry_initial_prompt == true)
            let promptStr = wparams.initial_prompt.map { String(cString: $0) }
            #expect(promptStr == "Schaufelgeometrie, Kurbelgehäuse")
        }
    }

    @Test("Language normalization treats nil, empty, whitespace, and auto (any case) as nil")
    func testLanguageNormalization() {
        for rawLang in [nil, "", "   ", "auto", "AUTO", " Auto \n"] {
            let options = TranscriptionOptions(language: rawLang)
            WhisperCppEngine.withWhisperParams(options: options) { wparams in
                #expect(wparams.language == nil)
            }
        }

        let explicit = TranscriptionOptions(language: " de ")
        WhisperCppEngine.withWhisperParams(options: explicit) { wparams in
            let langStr = wparams.language.map { String(cString: $0) }
            #expect(langStr == "de")
        }
    }

    @Test("Uppercase and mixed-case language codes normalize to lowercase and resolve valid whisper_lang_id")
    func testUppercaseLanguageNormalization() {
        #expect(WhisperCppEngine.normalizeLanguage(nil) == nil)
        #expect(WhisperCppEngine.normalizeLanguage("") == nil)
        #expect(WhisperCppEngine.normalizeLanguage("  \n ") == nil)
        #expect(WhisperCppEngine.normalizeLanguage("AUTO") == nil)
        #expect(WhisperCppEngine.normalizeLanguage("DE") == "de")
        #expect(WhisperCppEngine.normalizeLanguage(" En ") == "en")

        let upperGerman = TranscriptionOptions(language: "DE")
        WhisperCppEngine.withWhisperParams(options: upperGerman) { wparams in
            let langStr = wparams.language.map { String(cString: $0) }
            #expect(langStr == "de")
            if let ptr = wparams.language {
                #expect(whisper_lang_id(ptr) >= 0)
                #expect(whisper_lang_id(ptr) == whisper_lang_id("de"))
            }
        }
    }

    @Test("Segment noSpeechProb decodes cleanly from legacy JSON and round-trips when present")
    func testSegmentNoSpeechProbCompatibility() throws {
        let legacyJSON = """
        {
            "start": 1.0,
            "end": 2.5,
            "text": "Gittermodell erstellt."
        }
        """
        let legacyData = try #require(legacyJSON.data(using: .utf8))
        let legacySegment = try JSONDecoder().decode(Segment.self, from: legacyData)
        #expect(legacySegment.noSpeechProb == nil)

        let segmentWithProb = Segment(start: 1.0, end: 2.5, text: "Gittermodell erstellt.", noSpeechProb: 0.18)
        let encoded = try JSONEncoder().encode(segmentWithProb)
        let decoded = try JSONDecoder().decode(Segment.self, from: encoded)
        #expect(decoded == segmentWithProb)
        #expect(decoded.noSpeechProb == 0.18)
    }

    @Test("WhisperCppEngine throws modelNotFound for missing model path")
    func testMissingModelThrows() {
        #expect(throws: WhisperCppError.self) {
            _ = try WhisperCppEngine(modelPath: "/nonexistent/path/ggml-missing.bin")
        }
    }

    @Test("TranscriptionCancellationToken handles rapid concurrent cancellation safely")
    func testConcurrentCancellationToken() async {
        let token = TranscriptionCancellationToken()
        #expect(token.isCancelled == false)

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    if i % 5 == 0 {
                        token.cancel()
                    } else {
                        _ = token.isCancelled
                    }
                }
            }
        }

        #expect(token.isCancelled == true)
    }
}
