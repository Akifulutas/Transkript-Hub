import Testing
import Foundation
import GRDB
@testable import TranskriptHubCore

@Suite("Smart Transcript Cache and Deduplication Test Suite")
struct TranscriptCacheTests {
    
    private func makeTestDatabase() throws -> AppDatabase {
        var config = Configuration()
        config.qos = .userInitiated
        let queue = try DatabaseQueue(configuration: config)
        return try AppDatabase(queue)
    }
    
    @Test("YouTube external_id cache match")
    func testYouTubeCacheHit() async throws {
        let db = try makeTestDatabase()
        let cache = TranscriptCacheManager(database: db)
        
        await cache.save(
            externalID: "TEST_VIDEO_123",
            title: "Great Swift Lecture",
            durationSec: 120.5,
            outputPath: "/path/to/output.md",
            transcriptText: "Hello world, this is a test transcript."
        )
        
        let found = await cache.findCached(
            title: "Great Swift Lecture",
            durationSec: 120.5,
            externalID: "TEST_VIDEO_123"
        )
        
        #expect(found != nil)
        #expect(found?.transcriptText == "Hello world, this is a test transcript.")
        #expect(found?.externalID == "TEST_VIDEO_123")
    }
    
    @Test("Audio file smart matching by title and duration")
    func testAudioDurationAndNameMatch() async throws {
        let db = try makeTestDatabase()
        let cache = TranscriptCacheManager(database: db)
        
        // Sample recording: 45.2 seconds
        await cache.save(
            externalID: "/Users/test/Voice Recording 1.m4a",
            title: "Voice Recording 1",
            durationSec: 45.2,
            sourcePath: "/Users/test/Voice Recording 1.m4a",
            outputPath: "/Users/test/Transkript/Voice Recording 1.md",
            transcriptText: "First transcription of this recording."
        )
        
        // 1. Same title and duration (within 0.2s tolerance) -> Must match!
        let match1 = await cache.findCached(
            title: "Voice Recording 1",
            durationSec: 45.3,
            sourcePath: "/Users/other/Downloads/Voice Recording 1.m4a"
        )
        #expect(match1 != nil)
        #expect(match1?.transcriptText == "First transcription of this recording.")
        
        // 2. Same title but completely different duration (e.g. 120s) -> Must NOT match!
        let mismatchDuration = await cache.findCached(
            title: "Voice Recording 1",
            durationSec: 120.0,
            sourcePath: "/Users/other/Downloads/Voice Recording 1.m4a"
        )
        #expect(mismatchDuration == nil)
        
        // 3. Same duration but completely unrelated title -> Must NOT match
        let mismatchName = await cache.findCached(
            title: "Unrelated File",
            durationSec: 45.2,
            sourcePath: "/Users/test/Unrelated.m4a"
        )
        #expect(mismatchName == nil)
    }
    
    @Test("Automatic recovery from legacy completed jobs")
    func testFallbackToCompletedJobs() async throws {
        let db = try makeTestDatabase()
        let cache = TranscriptCacheManager(database: db)
        
        // Insert a completed legacy job directly into SQLite
        try await db.dbQueue.write { db in
            try BatchRecord(
                id: "OLD_BATCH",
                createdAt: ISO8601DateFormatter().string(from: Date()),
                kind: .files,
                expectedCount: 1,
                state: .completed,
                outputPath: "/old/batch.md"
            ).insert(db)
            
            try JobRecord(
                id: "OLD_JOB_1",
                batchID: "OLD_BATCH",
                sequence: 1,
                sourceType: "audio",
                sourcePath: "/old/voice_memo.m4a",
                title: "voice_memo",
                durationSec: 88.0,
                state: .completed
            ).insert(db)
            
            try TranscriptSectionRecord(
                jobID: "OLD_JOB_1",
                text: "Recovered transcript content from database."
            ).insert(db)
        }
        
        let recovered = await cache.findCached(
            title: "voice_memo",
            durationSec: 88.0,
            sourcePath: "/Users/user/Desktop/voice_memo.m4a"
        )
        
        #expect(recovered != nil)
        #expect(recovered?.transcriptText == "Recovered transcript content from database.")
    }
    
    @Test("Updating cache on re-transcription replaces previous transcript")
    func testReTranscriptionCacheUpdate() async throws {
        let db = try makeTestDatabase()
        let cache = TranscriptCacheManager(database: db)
        
        await cache.save(
            externalID: "RETRY_ITEM_1",
            title: "Meeting Note",
            durationSec: 60.0,
            sourcePath: "/path/to/meeting.mp4",
            outputPath: "/path/to/meeting.txt",
            transcriptText: "Old transcript text."
        )
        
        let initial = await cache.findCached(
            title: "Meeting Note",
            durationSec: 60.0,
            externalID: "RETRY_ITEM_1"
        )
        #expect(initial?.transcriptText == "Old transcript text.")
        
        // Re-transcribe with improved text
        await cache.save(
            externalID: "RETRY_ITEM_1",
            title: "Meeting Note",
            durationSec: 60.0,
            sourcePath: "/path/to/meeting.mp4",
            outputPath: "/path/to/meeting.txt",
            transcriptText: "New improved re-transcribed text."
        )
        
        let updated = await cache.findCached(
            title: "Meeting Note",
            durationSec: 60.0,
            externalID: "RETRY_ITEM_1"
        )
        #expect(updated?.transcriptText == "New improved re-transcribed text.")
    }
}
