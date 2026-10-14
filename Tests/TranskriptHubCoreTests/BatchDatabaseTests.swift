import Foundation
import Testing
import GRDB
@testable import TranskriptHubCore

@Test func testDatabaseMigrationsAndBatchCreation() async throws {
    let appDb = try AppDatabase.makeInMemory()
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let writer = OutputWriter(customOutputDirectory: tempDir)
    let jobManager = JobManager(database: appDb, outputWriter: writer)
    
    let urls = [
        "https://www.youtube.com/watch?v=11111111111",
        "https://www.youtube.com/watch?v=22222222222"
    ]
    
    let batch = try await jobManager.createYouTubeBatch(urls: urls, language: "tr")
    #expect(batch.expectedCount == 2)
    #expect(batch.kind == "youtube")
    
    let jobs = try await appDb.dbQueue.read { db in
        try JobRecord.filter(Column("batch_id") == batch.id).order(Column("sequence")).fetchAll(db)
    }
    #expect(jobs.count == 2)
    #expect(jobs[0].sequence == 1)
    #expect(jobs[1].sequence == 2)
    #expect(jobs[0].externalID == "11111111111")
    #expect(jobs[1].externalID == "22222222222")
}

@Test func testPartialBatchAssemblyWithFailedVideos() async throws {
    // Simulating the 22/25 failure scenario in-memory
    let appDb = try AppDatabase.makeInMemory()
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let writer = OutputWriter(customOutputDirectory: tempDir)
    
    let batchID = "TEST-BATCH-PARTIAL"
    let batch = BatchRecord(
        id: batchID,
        expectedCount: 3,
        state: .active,
        language: "tr"
    )
    
    let job1 = JobRecord(
        id: "job-1",
        batchID: batchID,
        sequence: 1,
        sourceURL: "https://www.youtube.com/watch?v=aaaaa111111",
        title: "Birinci Başarılı Video",
        creator: "Kanal A",
        durationSec: 60,
        state: .completed
    )
    
    let job2 = JobRecord(
        id: "job-2",
        batchID: batchID,
        sequence: 2,
        sourceURL: "https://www.youtube.com/watch?v=bbbbb222222",
        title: "İkinci Başarısız Video",
        creator: "Kanal B",
        state: .failed,
        errorKind: "videoUnavailable",
        errorMessage: "HTTP 403: Forbidden / Üyelik gerekiyor"
    )
    
    let job3 = JobRecord(
        id: "job-3",
        batchID: batchID,
        sequence: 3,
        sourceURL: "https://www.youtube.com/watch?v=ccccc333333",
        title: "Üçüncü Başarılı Video",
        creator: "Kanal C",
        durationSec: 120,
        state: .completed
    )
    
    try await appDb.dbQueue.write { db in
        try batch.insert(db)
        try job1.insert(db)
        try job2.insert(db)
        try job3.insert(db)
        
        let sec1 = TranscriptSectionRecord(jobID: "job-1", text: "Birinci videonun metni buradadır.")
        let sec3 = TranscriptSectionRecord(jobID: "job-3", text: "Üçüncü videonun metni buradadır.")
        try sec1.insert(db)
        try sec3.insert(db)
    }
    
    let assembler = BatchAssembler(database: appDb, outputWriter: writer)
    let result = try assembler.assembleBatch(batchID: batchID, modelName: "tiny")
    
    switch result {
    case .assembled(let outputURL, let isPartial):
        #expect(isPartial == true)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        
        let content = try String(contentsOf: outputURL, encoding: .utf8)
        #expect(content.contains("Completed: 2"))
        #expect(content.contains("Failed: 1"))
        #expect(content.contains("Birinci Başarılı Video"))
        #expect(content.contains("Birinci videonun metni buradadır."))
        #expect(content.contains("STATUS: İŞLENEMEDİ — HTTP 403: Forbidden / Üyelik gerekiyor"))
        #expect(content.contains("Üçüncü Başarılı Video"))
        #expect(content.contains("Üçüncü videonun metni buradadır."))
    default:
        Issue.record("Beklenen .assembled sonucu alınamadı.")
    }
    
    // Test cleanup
    let cleanupManager = CleanupManager(database: appDb)
    try cleanupManager.cleanupBatch(batchID: batchID)
    
    let cleanedBatch = try await appDb.dbQueue.read { db in
        try BatchRecord.fetchOne(db, key: batchID)
    }
    #expect(cleanedBatch?.cleanedAt != nil)
    #expect(cleanedBatch?.state == BatchState.completedWithErrors.rawValue)
}
