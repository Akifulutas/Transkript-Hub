import Foundation
import Testing
@testable import TranskriptHubCore

@Suite("Transcript PostProcessor Comprehensive Test Suite")
struct PostProcessorDeepTests {
    
    @Test("Noise and background tag removal")
    func testNoiseTagsRemovalComprehensive() {
        let processor = TranscriptPostProcessor()
        let rawSegments = [
            Segment(start: 0.0, end: 2.0, text: "[Music]"),
            Segment(start: 2.0, end: 5.0, text: "Hello viewers [Applause] welcome to the program."),
            Segment(start: 5.0, end: 7.0, text: "(Laughter) Today we will discuss artificial intelligence."),
            Segment(start: 7.0, end: 9.0, text: "[Music] [Applause] Moving on."),
            Segment(start: 9.0, end: 11.0, text: "*music* Background audio should be cleaned."),
            Segment(start: 11.0, end: 13.0, text: "♪ upbeat music ♪"),
            Segment(start: 13.0, end: 15.0, text: "Concluding sentence.")
        ]
        
        let result = processor.process(segments: rawSegments)
        
        // Tags must be stripped
        #expect(!result.contains("[Music]"))
        #expect(!result.contains("[Applause]"))
        #expect(!result.contains("(Laughter)"))
        #expect(!result.contains("*music*"))
        #expect(!result.contains("♪"))
        
        // Core dialogue must be preserved
        #expect(result.contains("Hello viewers"))
        #expect(result.contains("welcome to the program."))
        #expect(result.contains("Today we will discuss artificial intelligence."))
        #expect(result.contains("Moving on."))
        #expect(result.contains("Concluding sentence."))
    }
    
    @Test("Whisper hallucination repetition loop break")
    func testRepetitionLoopBreak() {
        let processor = TranscriptPostProcessor()
        var segments: [Segment] = [
            Segment(start: 0.0, end: 2.0, text: "Introduction starts."),
            Segment(start: 2.0, end: 4.0, text: "Topic explanation.")
        ]
        
        // Add identical hallucinated segment 10 times consecutively
        for i in 1...10 {
            segments.append(
                Segment(start: Double(4 + i), end: Double(5 + i), text: "Please subscribe to the channel.")
            )
        }
        
        segments.append(Segment(start: 20.0, end: 22.0, text: "Outro completed."))
        
        let result = processor.process(segments: segments)
        
        // Repeated sentence should appear at most twice rather than 10 times
        let occurrences = result.components(separatedBy: "Please subscribe to the channel.").count - 1
        #expect(occurrences <= 2, "Repetition loop was not broken, count: \(occurrences)")
        #expect(result.contains("Introduction starts."))
        #expect(result.contains("Outro completed."))
    }
    
    @Test("Paragraph chunking based on silence threshold")
    func testParagraphChunkingWithSilenceThreshold() {
        let processor = TranscriptPostProcessor()
        let segments = [
            Segment(start: 0.0, end: 5.0, text: "First topic is being discussed."),
            Segment(start: 5.0, end: 10.0, text: "Second sentence ends right here."),
            // 20s long silence gap -> with threshold 2.0s, triggers a new paragraph
            Segment(start: 30.0, end: 35.0, text: "After a long pause, a new subject begins.")
        ]
        
        let options = PostProcessorOptions(paragraphSilenceThreshold: 2.0)
        let result = processor.process(segments: segments, options: options)
        
        // Two paragraphs should be separated by double line break (\n\n)
        let paragraphs = result.components(separatedBy: "\n\n")
        #expect(paragraphs.count >= 2, "Paragraph division was not created")
        #expect(paragraphs[0].contains("First topic"))
        #expect(paragraphs[1].contains("After a long pause"))
    }
}
