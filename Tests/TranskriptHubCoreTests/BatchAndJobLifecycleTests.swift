import Foundation
import Testing
import GRDB
@testable import TranskriptHubCore

@Suite("İş Kuyruğu ve SQLite Yaşam Döngüsü (Batch & Job Lifecycle) Test Paketi")
struct BatchAndJobLifecycleTests {
    
    @Test("İş kuyruğunda kesinti sonrası kurtarma (Crash Recovery)")
    func testCrashRecoveryMechanism() async throws {
        let appDb = try AppDatabase.makeInMemory()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let writer = OutputWriter(customOutputDirectory: tempDir)
        let jobManager = JobManager(database: appDb, outputWriter: writer)
        
        let batchID = "BATCH-CRASH-TEST"
        let batch = BatchRecord(id: batchID, expectedCount: 2, state: .active, language: "tr")
        
        // Uygulama aniden kapandığında 'fetching' veya 'transcribing' durumunda kalan işler
        let job1 = JobRecord(
            id: "job-stuck-fetch",
            batchID: batchID,
            sequence: 1,
            sourceURL: "https://www.youtube.com/watch?v=11111111111",
            state: .fetching,
            attempt: 0
        )
        
        let job2 = JobRecord(
            id: "job-stuck-transcribe",
            batchID: batchID,
            sequence: 2,
            sourceURL: "https://www.youtube.com/watch?v=22222222222",
            state: .transcribing,
            attempt: 1
        )
        
        try await appDb.dbQueue.write { db in
            try batch.insert(db)
            try job1.insert(db)
            try job2.insert(db)
        }
        
        // Uygulama yeniden başlatıldığında recoverState() çağrılır
        try await jobManager.recoverState()
        
        let recoveredJobs = try await appDb.dbQueue.read { db in
            try JobRecord.filter(Column("batch_id") == batchID).order(Column("sequence")).fetchAll(db)
        }
        
        #expect(recoveredJobs.count == 2)
        // fetching -> queued, transcribing -> fetched
        #expect(recoveredJobs[0].state == JobState.queued.rawValue)
        #expect(recoveredJobs[1].state == JobState.fetched.rawValue)
    }
    
    @Test("Kısmi başarı durumunda hata raporu ve başarılı transkriptlerin birleştirilmesi")
    func testPartialFailureBatchAssembly() async throws {
        let appDb = try AppDatabase.makeInMemory()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let writer = OutputWriter(customOutputDirectory: tempDir)
        
        let batchID = "BATCH-PARTIAL-FAIL"
        let batch = BatchRecord(id: batchID, expectedCount: 3, state: .active, language: "tr")
        
        let job1 = JobRecord(
            id: "j1",
            batchID: batchID,
            sequence: 1,
            sourceURL: "https://www.youtube.com/watch?v=aaaaa111111",
            title: "Başarılı Bölüm 1",
            creator: "Yazar A",
            durationSec: 120,
            state: .completed
        )
        
        let job2 = JobRecord(
            id: "j2",
            batchID: batchID,
            sequence: 2,
            sourceURL: "https://www.youtube.com/watch?v=bbbbb222222",
            title: "Gizli / Engelli Video",
            creator: "Yazar B",
            durationSec: 0,
            state: .failed,
            errorKind: "videoUnavailable",
            errorMessage: "HTTP 403: Forbidden"
        )
        
        let job3 = JobRecord(
            id: "j3",
            batchID: batchID,
            sequence: 3,
            sourceURL: "https://www.youtube.com/watch?v=ccccc333333",
            title: "Başarılı Bölüm 2",
            creator: "Yazar A",
            durationSec: 180,
            state: .completed
        )
        
        try await appDb.dbQueue.write { db in
            try batch.insert(db)
            try job1.insert(db)
            try job2.insert(db)
            try job3.insert(db)
            
            // Başarılı olanların transkript kayıtları
            try TranscriptSectionRecord(
                jobID: "j1",
                text: "Bu birinci bölümün konuşma metnidir."
            ).insert(db)
            
            try TranscriptSectionRecord(
                jobID: "j3",
                text: "Bu üçüncü bölümün konuşma metnidir."
            ).insert(db)
        }
        
        let assembler = BatchAssembler(database: appDb, outputWriter: writer)
        let result = try await assembler.assembleBatch(batchID: batchID)
        
        switch result {
        case .assembled(let fileURL, let isPartial):
            #expect(isPartial == true, "3 videodan 1'i başarısız olduğu için isPartial true olmalıydı")
            #expect(FileManager.default.fileExists(atPath: fileURL.path))
            
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            
            // Başarılı içerikler metinde yer almalı
            #expect(content.contains("Başarılı Bölüm 1"))
            #expect(content.contains("Bu birinci bölümün konuşma metnidir."))
            #expect(content.contains("Başarılı Bölüm 2"))
            #expect(content.contains("Bu üçüncü bölümün konuşma metnidir."))
            
            // Başarısız videonun uyarısı ve gerekçesi raporda açıkça yer almalı
            #expect(content.contains("Failed: 1"))
            #expect(content.contains("STATUS: İŞLENEMEDİ — HTTP 403: Forbidden"))
            
        default:
            Issue.record("Beklenen .assembled sonucu alınamadı")
        }
    }
}
