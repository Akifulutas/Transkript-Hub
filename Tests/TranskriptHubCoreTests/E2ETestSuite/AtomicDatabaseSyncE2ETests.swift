import Foundation
import Testing
import GRDB
@testable import TranskriptHubCore

// MARK: - Database Sync Error & Test Helpers

public enum DatabaseSyncError: Error, LocalizedError, Equatable {
    case jobNotFound(String)
    case simulatedWriteFailure
    
    public var errorDescription: String? {
        switch self {
        case .jobNotFound(let id):
            return "İş ID bulunamadı: \(id)"
        case .simulatedWriteFailure:
            return "Simüle edilen yazma hatası (Rollback testi)."
        }
    }
}

extension AppDatabase {
    /// Atomic transcript update conforming to PROJECT.md interface contract
    public func updateTranscript(
        jobId: String,
        newText: String,
        segmentsJSON: String?
    ) async throws {
        try await dbQueue.write { db in
            guard let _ = try JobRecord.fetchOne(db, key: jobId) else {
                throw DatabaseSyncError.jobNotFound(jobId)
            }
            
            let section = TranscriptSectionRecord(jobID: jobId, text: newText, segments: segmentsJSON)
            try section.save(db)
            
            let now = ISO8601DateFormatter().string(from: Date())
            try db.execute(
                sql: "UPDATE job SET updated_at = :now WHERE id = :jobId",
                arguments: ["now": now, "jobId": jobId]
            )
        }
    }
    
    /// Simulated failing atomic transaction to verify rollback guarantee
    public func failingUpdateTranscript(
        jobId: String,
        newText: String
    ) async throws {
        try await dbQueue.write { db in
            let section = TranscriptSectionRecord(jobID: jobId, text: newText, segments: nil)
            try section.save(db)
            
            // Intentionally throw midway through transaction before commit
            throw DatabaseSyncError.simulatedWriteFailure
        }
    }
}

// MARK: - Test Suite

@Suite("Atomic Database Sync E2E Test Suite")
struct AtomicDatabaseSyncE2ETests {
    
    @Test("Atomic transcript update cleanly updates database model without corruption")
    func testAtomicTranscriptSectionUpdate() async throws {
        let appDb = try AppDatabase.makeInMemory()
        
        let batchId = "BATCH-ATOMIC-1"
        let jobId = "JOB-ATOMIC-1"
        
        try await appDb.dbQueue.write { db in
            let batch = BatchRecord(id: batchId, expectedCount: 1, state: .active)
            try batch.insert(db)
            
            let job = JobRecord(
                id: jobId,
                batchID: batchId,
                sequence: 1,
                title: "İlk Kayıt",
                state: .completed,
                updatedAt: "2026-10-15T12:00:00Z"
            )
            try job.insert(db)
            
            let initialSection = TranscriptSectionRecord(
                jobID: jobId,
                text: "Eski metin buradaydı.",
                segments: "[]"
            )
            try initialSection.insert(db)
        }
        
        // Execute atomic update
        let updatedText = "Yeni düzeltilmiş metin burada yer alıyor."
        let updatedSegmentsJSON = "[{\"start\":0.0,\"end\":3.5,\"text\":\"Yeni düzeltilmiş metin\",\"speaker\":\"Speaker 1\"}]"
        
        try await appDb.updateTranscript(
            jobId: jobId,
            newText: updatedText,
            segmentsJSON: updatedSegmentsJSON
        )
        
        // Verify in database
        let section = try await appDb.dbQueue.read { db in
            try TranscriptSectionRecord.fetchOne(db, key: jobId)
        }
        
        #expect(section != nil)
        #expect(section?.text == updatedText)
        #expect(section?.segments == updatedSegmentsJSON)
        
        let job = try await appDb.dbQueue.read { db in
            try JobRecord.fetchOne(db, key: jobId)
        }
        #expect(job?.updatedAt != "2026-10-15T12:00:00Z", "Job updatedAt timestamp must be refreshed on transcript update")
    }
    
    @Test("Transaction rollback guarantee: failure restores prior state completely")
    func testTransactionRollbackOnFailure() async throws {
        let appDb = try AppDatabase.makeInMemory()
        let batchId = "BATCH-ROLLBACK"
        let jobId = "JOB-ROLLBACK"
        let originalText = "Orijinal bozulmamış metin."
        
        try await appDb.dbQueue.write { db in
            let batch = BatchRecord(id: batchId, expectedCount: 1, state: .active)
            try batch.insert(db)
            
            let job = JobRecord(id: jobId, batchID: batchId, sequence: 1, title: "Rollback Testi")
            try job.insert(db)
            
            let initialSection = TranscriptSectionRecord(jobID: jobId, text: originalText, segments: nil)
            try initialSection.insert(db)
        }
        
        // Attempt failing update that throws mid-transaction
        await #expect(throws: DatabaseSyncError.simulatedWriteFailure) {
            try await appDb.failingUpdateTranscript(jobId: jobId, newText: "BU METIN ASLA KAYDEDİLMEMELİDİR.")
        }
        
        // Verify state is 100% rolled back to originalText
        let currentSection = try await appDb.dbQueue.read { db in
            try TranscriptSectionRecord.fetchOne(db, key: jobId)
        }
        
        #expect(currentSection?.text == originalText, "Transaction failure must roll back and preserve original text")
    }
    
    @Test("Concurrent reads during active writing never observe partial or corrupt states")
    func testConcurrentReadsDuringActiveWrite() async throws {
        let appDb = try AppDatabase.makeInMemory()
        let batchId = "BATCH-CONCURRENT"
        let jobId = "JOB-CONCURRENT"
        
        try await appDb.dbQueue.write { db in
            let batch = BatchRecord(id: batchId, expectedCount: 1, state: .active)
            try batch.insert(db)
            let job = JobRecord(id: jobId, batchID: batchId, sequence: 1, title: "Concurrent Test")
            try job.insert(db)
            let initialSection = TranscriptSectionRecord(jobID: jobId, text: "Initial text 0")
            try initialSection.insert(db)
        }
        
        // Execute 25 writes in parallel with concurrent reads
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Reader tasks
            for _ in 1...5 {
                group.addTask {
                    for _ in 1...20 {
                        let sec = try await appDb.dbQueue.read { db in
                            try TranscriptSectionRecord.fetchOne(db, key: jobId)
                        }
                        #expect(sec != nil)
                        #expect(sec!.text.hasPrefix("Version ") || sec!.text == "Initial text 0")
                    }
                }
            }
            
            // Writer task
            group.addTask {
                for version in 1...25 {
                    let versionText = "Version \(version): Metin güncellendi."
                    try await appDb.updateTranscript(
                        jobId: jobId,
                        newText: versionText,
                        segmentsJSON: "[]"
                    )
                }
            }
            
            try await group.waitForAll()
        }
        
        let finalSection = try await appDb.dbQueue.read { db in
            try TranscriptSectionRecord.fetchOne(db, key: jobId)
        }
        #expect(finalSection?.text == "Version 25: Metin güncellendi.")
    }
    
    @Test("Large transcript payload (500 segments, 5000 words) persists without truncation")
    func testLargeTranscriptPayloadIntegrity() async throws {
        let appDb = try AppDatabase.makeInMemory()
        let batchId = "BATCH-LARGE"
        let jobId = "JOB-LARGE"
        
        try await appDb.dbQueue.write { db in
            let batch = BatchRecord(id: batchId, expectedCount: 1, state: .active)
            try batch.insert(db)
            let job = JobRecord(id: jobId, batchID: batchId, sequence: 1, title: "Large Transcript")
            try job.insert(db)
        }
        
        // Build 500 segments with nested words
        var largeSegments: [DiarizedSegment] = []
        largeSegments.reserveCapacity(500)
        
        for segIdx in 0..<500 {
            let segStart = Double(segIdx) * 5.0
            let segEnd = segStart + 4.8
            let words = (0..<10).map { wIdx in
                WordItem(
                    text: "kelime_\(segIdx)_\(wIdx)",
                    start: segStart + Double(wIdx) * 0.45,
                    end: segStart + Double(wIdx) * 0.45 + 0.4,
                    confidence: 0.95
                )
            }
            largeSegments.append(
                DiarizedSegment(
                    start: segStart,
                    end: segEnd,
                    text: words.map(\.text).joined(separator: " "),
                    speaker: "Speaker \((segIdx % 3) + 1)",
                    words: words
                )
            )
        }
        
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(largeSegments)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        let fullText = largeSegments.map(\.text).joined(separator: "\n")
        
        // Update database
        try await appDb.updateTranscript(jobId: jobId, newText: fullText, segmentsJSON: jsonString)
        
        // Fetch back and verify
        let fetched = try await appDb.dbQueue.read { db in
            try TranscriptSectionRecord.fetchOne(db, key: jobId)
        }
        
        #expect(fetched != nil)
        #expect(fetched?.text == fullText)
        
        let decoder = JSONDecoder()
        let fetchedSegments = try decoder.decode([DiarizedSegment].self, from: Data(fetched!.segments!.utf8))
        #expect(fetchedSegments.count == 500)
        #expect(fetchedSegments[250].words.count == 10)
        #expect(fetchedSegments[499].speaker == "Speaker \((499 % 3) + 1)")
    }
    
    @Test("Cascade deletion automatically removes transcript sections when parent batch is deleted")
    func testCascadeDeletionSafety() async throws {
        let appDb = try AppDatabase.makeInMemory()
        let batchId = "BATCH-CASCADE"
        let jobId = "JOB-CASCADE"
        
        try await appDb.dbQueue.write { db in
            let batch = BatchRecord(id: batchId, expectedCount: 1, state: .active)
            try batch.insert(db)
            let job = JobRecord(id: jobId, batchID: batchId, sequence: 1, title: "Cascade Job")
            try job.insert(db)
            let section = TranscriptSectionRecord(jobID: jobId, text: "Metin", segments: nil)
            try section.insert(db)
        }
        
        // Delete batch
        try await appDb.dbQueue.write { db in
            _ = try BatchRecord.deleteOne(db, key: batchId)
        }
        
        // Verify job and transcript_section are cascade deleted
        let remainingJob = try await appDb.dbQueue.read { db in
            try JobRecord.fetchOne(db, key: jobId)
        }
        let remainingSection = try await appDb.dbQueue.read { db in
            try TranscriptSectionRecord.fetchOne(db, key: jobId)
        }
        
        #expect(remainingJob == nil, "Job must be cascade deleted")
        #expect(remainingSection == nil, "TranscriptSection must be cascade deleted")
    }
}
