import Foundation
import Testing
@testable import TranskriptHubCore

@Test func testSegmentAndTranscriptResult() async throws {
    let segment1 = Segment(start: 0.0, end: 2.5, text: "Merhaba")
    let segment2 = Segment(start: 2.6, end: 5.0, text: "Dünya")
    let result = TranscriptResult(segments: [segment1, segment2], detectedLanguage: "tr")
    
    #expect(result.detectedLanguage == "tr")
    #expect(result.segments.count == 2)
    #expect(result.fullText == "Merhaba Dünya")
}

@Test func testPostProcessorNoiseTags() async throws {
    let postProcessor = TranscriptPostProcessor()
    let segments = [
        Segment(start: 0.0, end: 1.0, text: "[Music] Merhaba arkadaşlar [BLANK_AUDIO]"),
        Segment(start: 1.2, end: 2.5, text: "Bugün hava çok güzel (alkış)")
    ]
    
    let processed = postProcessor.process(segments: segments)
    #expect(!processed.contains("[Music]"))
    #expect(!processed.contains("[BLANK_AUDIO]"))
    #expect(!processed.contains("(alkış)"))
    #expect(processed.contains("Merhaba arkadaşlar"))
    #expect(processed.contains("Bugün hava çok güzel"))
}

@Test func testPostProcessorRepetitionLoop() async throws {
    let postProcessor = TranscriptPostProcessor()
    let segments = [
        Segment(start: 0.0, end: 1.0, text: "Evet"),
        Segment(start: 1.0, end: 2.0, text: "Evet"),
        Segment(start: 2.0, end: 3.0, text: "Evet"),
        Segment(start: 3.0, end: 4.0, text: "Evet"),
        Segment(start: 4.0, end: 5.0, text: "Sonraki cümle.")
    ]
    
    let processed = postProcessor.process(segments: segments)
    let occurrences = processed.components(separatedBy: "Evet").count - 1
    #expect(occurrences <= 2)
    #expect(processed.contains("Sonraki cümle."))
}

@Test func testModelManagerFileNames() async throws {
    let manager = ModelManager(modelsDirectory: URL(fileURLWithPath: "/tmp/test_models"))
    #expect(manager.localURL(for: .tiny).lastPathComponent == "ggml-tiny.bin")
    #expect(manager.localURL(for: .base).lastPathComponent == "ggml-base.bin")
    #expect(manager.localURL(for: .largeV3Turbo).lastPathComponent == "ggml-large-v3-turbo.bin")
    #expect(manager.localURL(for: .largeV3TurboQ5).lastPathComponent == "ggml-large-v3-turbo-q5_0.bin")
}
