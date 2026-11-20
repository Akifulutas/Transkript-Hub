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
    
    @Test("Bidirectional substring titles (e.g. Recording 2 vs Recording 20) do NOT collide in cache")
    func testNoFalsePositiveSubstringTitleCollision() async throws {
        let db = try makeTestDatabase()
        let cache = TranscriptCacheManager(database: db)
        
        await cache.save(
            externalID: "/Users/test/Recording 2.m4a",
            title: "Recording 2",
            durationSec: 60.0,
            sourcePath: "/Users/test/Recording 2.m4a",
            outputPath: "/Users/test/Transkript/Recording 2.txt",
            modelID: "large-v3-q5_0",
            languageCode: "de",
            transcriptText: "Transcript for Recording 2."
        )
        
        // "Recording 20" contains "Recording 2" as a prefix and has the same duration (60.0s),
        // but is a distinct recording and must NOT hit the cache for "Recording 2"!
        let falseHit1 = await cache.findCached(
            title: "Recording 20",
            durationSec: 60.0,
            sourcePath: "/Users/test/Recording 20.m4a",
            modelID: "large-v3-q5_0",
            languageCode: "de"
        )
        #expect(falseHit1 == nil)
        
        // "Recording" is a substring of "Recording 2", must also NOT collide!
        let falseHit2 = await cache.findCached(
            title: "Recording",
            durationSec: 60.0,
            sourcePath: "/Users/test/Recording.m4a",
            modelID: "large-v3-q5_0",
            languageCode: "de"
        )
        #expect(falseHit2 == nil)
    }
    
    @Test("Model-aware and content-hash-aware cache lookup prevents stale cross-model hits")
    func testModelAndContentHashAwareCache() async throws {
        let db = try makeTestDatabase()
        let cache = TranscriptCacheManager(database: db)
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cache_hash_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let fileA = tempDir.appendingPathComponent("lecture.m4a")
        try Data("audio-content-alpha-12345".utf8).write(to: fileA)
        let hashA = TranscriptCacheManager.computeFastContentHash(forPath: fileA.path)
        #expect(hashA != nil)
        
        await cache.save(
            externalID: fileA.path,
            title: "lecture",
            durationSec: 90.0,
            sourcePath: fileA.path,
            outputPath: tempDir.appendingPathComponent("lecture.txt").path,
            modelID: "large-v3-q5_0",
            languageCode: "de",
            transcriptText: "Transcript from Large-v3 Q5_0."
        )
        
        // Same file, same model -> HIT
        let hitSameModel = await cache.findCached(
            title: "lecture",
            durationSec: 90.0,
            sourcePath: fileA.path,
            externalID: fileA.path,
            modelID: "large-v3-q5_0",
            languageCode: "de"
        )
        #expect(hitSameModel?.transcriptText == "Transcript from Large-v3 Q5_0.")
        #expect(hitSameModel?.contentHash == hashA)
        
        // Same file, different model (qwen3-asr-1.7b) -> MISS (must re-transcribe with new model)
        let missDifferentModel = await cache.findCached(
            title: "lecture",
            durationSec: 90.0,
            sourcePath: fileA.path,
            externalID: fileA.path,
            modelID: "qwen3-asr-1.7b",
            languageCode: "de"
        )
        #expect(missDifferentModel == nil)
        
        // Overwrite fileA with completely different audio bytes but same path, title, and duration -> MISS
        try Data("completely-different-audio-bytes-99999".utf8).write(to: fileA)
        let missModifiedFile = await cache.findCached(
            title: "lecture",
            durationSec: 90.0,
            sourcePath: fileA.path,
            externalID: fileA.path,
            modelID: "large-v3-q5_0",
            languageCode: "de"
        )
        #expect(missModifiedFile == nil)
    }
}
