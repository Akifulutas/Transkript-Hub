import Foundation
import Testing
import GRDB
@testable import TranskriptHubCore

@Suite("Word Timestamp & Segment Synchronization Test Suite")
struct WordTimestampAndSegmentTests {
    
    @Test("Word struct properties, duration, contains, and identifier")
    func testWordPropertiesAndMethods() {
        let word = Word(text: "transcription", start: 1.25, end: 1.85, confidence: 0.98)
        
        #expect(word.text == "transcription")
        #expect(word.start == 1.25)
        #expect(word.end == 1.85)
        #expect(word.confidence == 0.98)
        #expect(abs(word.duration - 0.60) < 0.001)
        #expect(word.id == "1.25_1.85_transcription")
        
        // contains(time:) boundary checks
        #expect(word.contains(time: 1.25))
        #expect(word.contains(time: 1.50))
        #expect(word.contains(time: 1.85))
        #expect(!word.contains(time: 1.24))
        #expect(!word.contains(time: 1.86))
        #expect(!word.contains(time: 0.0))
        #expect(!word.contains(time: 10.0))
    }
    
    @Test("Segment backward compatibility with legacy JSON without words or speaker")
    func testSegmentBackwardCompatibilityDecodable() throws {
        let legacyJSON = """
        {
            "start": 0.0,
            "end": 3.5,
            "text": "Legacy transcript segment without words."
        }
        """
        
        let data = try #require(legacyJSON.data(using: .utf8))
        let segment = try JSONDecoder().decode(Segment.self, from: data)
        
        #expect(segment.start == 0.0)
        #expect(segment.end == 3.5)
        #expect(segment.text == "Legacy transcript segment without words.")
        #expect(segment.speaker == nil)
        #expect(segment.words.isEmpty)
        #expect(segment.duration == 3.5)
        #expect(segment.contains(time: 2.0))
    }
    
    @Test("Segment JSON serialization preserves words, speaker, and timestamps")
    func testSegmentEncodingAndDecodingWithWordsAndSpeaker() throws {
        let words = [
            Word(text: "Native", start: 0.1, end: 0.5, confidence: 0.95),
            Word(text: "macOS", start: 0.6, end: 1.1, confidence: 0.99),
            Word(text: "App", start: 1.2, end: 1.5, confidence: 0.97)
        ]
        let original = Segment(start: 0.1, end: 1.5, text: "Native macOS App", speaker: "Speaker 1", words: words)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoded = try JSONDecoder().decode(Segment.self, from: data)
        #expect(decoded == original)
        #expect(decoded.speaker == "Speaker 1")
        #expect(decoded.words.count == 3)
        #expect(decoded.words[0].text == "Native")
        #expect(decoded.words[1].text == "macOS")
        #expect(decoded.words[2].text == "App")
    }
    
    @Test("Segment word lookup at specific playback timestamps")
    func testSegmentWordLookup() {
        let words = [
            Word(text: "Liquid", start: 1.0, end: 1.4),
            Word(text: "Glass", start: 1.5, end: 2.0)
        ]
        let segment = Segment(start: 1.0, end: 2.0, text: "Liquid Glass", words: words)
        
        #expect(segment.word(at: 1.0)?.text == "Liquid")
        #expect(segment.word(at: 1.2)?.text == "Liquid")
        #expect(segment.word(at: 1.4)?.text == "Liquid")
        #expect(segment.word(at: 1.45) == nil, "Pause interval between words should return nil")
        #expect(segment.word(at: 1.5)?.text == "Glass")
        #expect(segment.word(at: 2.0)?.text == "Glass")
        #expect(segment.word(at: 2.5) == nil)
    }
    
    @Test("Segment word interpolation fallback when token timestamps are absent")
    func testSegmentWordInterpolation() {
        // Empty text
        let emptyWords = Segment.interpolateWords(for: "", start: 0.0, end: 1.0)
        #expect(emptyWords.isEmpty)
        
        // Single word
        let singleWord = Segment.interpolateWords(for: "Hello", start: 1.0, end: 2.0)
        #expect(singleWord.count == 1)
        #expect(singleWord[0].text == "Hello")
        #expect(singleWord[0].start == 1.0)
        #expect(singleWord[0].end == 2.0)
        
        // Multiple words evenly distributed
        let words = Segment.interpolateWords(for: "Zero dependency architecture", start: 0.0, end: 3.0)
        #expect(words.count == 3)
        #expect(words[0].text == "Zero")
        #expect(words[1].text == "dependency")
        #expect(words[2].text == "architecture")
        #expect(words[0].start < words[0].end)
        #expect(words[0].end <= words[1].start)
        #expect(words[2].end == 3.0)
    }
    
    @Test("AppDatabase atomic transcript update and section fetch with segments")
    func testAppDatabaseTranscriptPersistence() async throws {
        let database = try AppDatabase.makeInMemory()
        
        // Create parent batch and job first
        let batchId = "TEST-BATCH-SEGMENTS"
        let jobId = "TEST-JOB-SEGMENTS"
        
        let batch = BatchRecord(
            id: batchId,
            expectedCount: 1,
            state: .completed,
            language: "tr"
        )
        
        let job = JobRecord(
            id: jobId,
            batchID: batchId,
            sequence: 1,
            sourceURL: "https://example.com/test.mp3",
            title: "Test Job",
            durationSec: 120,
            state: .completed
        )
        
        try await database.dbQueue.write { db in
            try batch.save(db)
            try job.save(db)
        }
        
        // Initially no transcript section
        let initialSection = try await database.fetchTranscriptSection(jobId: jobId)
        #expect(initialSection == nil)
        
        // Insert transcript with segments
        let segments = [
            Segment(
                start: 0.0,
                end: 2.0,
                text: "Apple Silicon transcription",
                speaker: "Speaker 1",
                words: [
                    Word(text: "Apple", start: 0.0, end: 0.5),
                    Word(text: "Silicon", start: 0.6, end: 1.2),
                    Word(text: "transcription", start: 1.3, end: 2.0)
                ]
            )
        ]
        
        try await database.updateTranscript(jobId: jobId, newText: "Apple Silicon transcription", segments: segments)
        
        // Verify fetched data
        let fetched = try await database.fetchTranscriptSection(jobId: jobId)
        let section = try #require(fetched)
        #expect(section.text == "Apple Silicon transcription")
        #expect(section.segments.count == 1)
        #expect(section.segments[0].speaker == "Speaker 1")
        #expect(section.segments[0].words.count == 3)
        #expect(section.segments[0].words[1].text == "Silicon")
        
        // Upsert overwrite check
        let updatedSegments = [
            Segment(start: 0.0, end: 2.0, text: "Updated text", speaker: "Speaker 2", words: [])
        ]
        try await database.updateTranscript(jobId: jobId, newText: "Updated text", segments: updatedSegments)
        
        let reFetched = try await database.fetchTranscriptSection(jobId: jobId)
        let updatedSection = try #require(reFetched)
        #expect(updatedSection.text == "Updated text")
        #expect(updatedSection.segments.count == 1)
        #expect(updatedSection.segments[0].speaker == "Speaker 2")
        #expect(updatedSection.segments[0].words.isEmpty)
    }
}
