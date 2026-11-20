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
    
    @Test("Alternating hallucination loop (Thank you / Thank you for watching) suppression")
    func testKnownHallucinationAlternatingLoopBreak() {
        let processor = TranscriptPostProcessor()
        let segments = [
            Segment(start: 0.0, end: 5.0, text: "Konuşma başladı ve ilk konu açıklandı."),
            Segment(start: 6.0, end: 7.0, text: "Thank you for watching."),
            Segment(start: 7.5, end: 8.5, text: "Thank you."),
            Segment(start: 9.0, end: 10.0, text: "Thank you for watching!"),
            Segment(start: 10.5, end: 11.5, text: "Thank you..."),
            Segment(start: 12.0, end: 13.0, text: "Thank you for watching."),
            Segment(start: 15.0, end: 20.0, text: "Sonuç bölümü ve değerlendirmeler tamamlandı.")
        ]
        
        let result = processor.process(segments: segments)
        
        #expect(result.contains("Konuşma başladı ve ilk konu açıklandı."))
        #expect(result.contains("Sonuç bölümü ve değerlendirmeler tamamlandı."))
        
        let thankYouCount = result.components(separatedBy: "Thank you").count - 1
        #expect(thankYouCount <= 2, "Alternating hallucination loop should be suppressed, found: \(thankYouCount)")
    }
    
    @Test("Pure German Whisper silence hallucination (göttliche Kraft) suppression")
    func testGermanSilencePureHallucinationSuppressed() {
        let processor = TranscriptPostProcessor()
        let segments = [
            Segment(start: 0.0, end: 5.0, text: "Vielen Dank."),
            Segment(start: 6.0, end: 10.0, text: "Ich hoffe, es hilft, es heilt die göttliche Kraft!"),
            Segment(start: 11.0, end: 16.0, text: "Hast du das mal simuliert? Ja, aber nicht ganz.")
        ]
        
        let result = processor.process(segments: segments)
        
        #expect(!result.contains("göttliche Kraft"), "Pure Whisper silence hallucination should be discarded completely")
        #expect(result.contains("Hast du das mal simuliert?"))
    }
    
    @Test("Intra-segment phrase deduplication collapses repeating clauses")
    func testIntraSegmentPhraseDeduplication() {
        let processor = TranscriptPostProcessor()
        let textWithRepeats = "was ich das mal so gut machen kann, was ich das mal so gut machen kann, was ich das mal so gut machen kann."
        
        let deduplicated = processor.deduplicatePhrases(textWithRepeats)
        
        let count = deduplicated.components(separatedBy: "was ich das mal so gut machen kann").count - 1
        #expect(count == 1, "Expected phrase to be collapsed to 1 occurrence, got \(count): \(deduplicated)")
        #expect(deduplicated.hasSuffix("."), "Should preserve terminal punctuation")
    }
    
    @Test("Intra-segment deduplication collapses repeating sentences and caps single word loops")
    func testIntraSegmentSentenceAndWordRepetitions() {
        let processor = TranscriptPostProcessor()
        
        // Multi-word sentence repeat
        let sentenceRepeat = "Fall 1: Maschine existiert. Fall 1: Maschine existiert."
        let cleanedSentence = processor.deduplicatePhrases(sentenceRepeat)
        let sentenceCount = cleanedSentence.components(separatedBy: "Maschine existiert").count - 1
        #expect(sentenceCount == 1, "Duplicate sentence should be collapsed: \(cleanedSentence)")
        
        // Single word excessive loop
        let wordLoop = "Ja. Ja. Ja. Ja. Ja. Ja. Ja. Ja."
        let cleanedWord = processor.deduplicatePhrases(wordLoop)
        let jaCount = cleanedWord.components(separatedBy: "Ja").count - 1
        #expect(jaCount <= 2, "Excessive single word loop should be capped to at most 2, got: \(jaCount)")
    }
}
