import Foundation
import Testing
import GRDB
@testable import TranskriptHubCore

@Suite("Batch and Job Lifecycle Test Suite")
struct BatchAndJobLifecycleTests {
    
    @Test("Crash recovery mechanism")
    func testCrashRecoveryMechanism() async throws {
        let appDb = try AppDatabase.makeInMemory()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let writer = OutputWriter(customOutputDirectory: tempDir)
        let jobManager = JobManager(database: appDb, outputWriter: writer)
        
        let batchID = "BATCH-CRASH-TEST"
        let batch = BatchRecord(id: batchID, expectedCount: 2, state: .active, language: "en")
        
        // Jobs left in 'fetching' or 'transcribing' state when the app was abruptly killed
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
        
        // recoverState() is executed when app relaunches
        try await jobManager.recoverState()
        
        let recoveredJobs = try await appDb.dbQueue.read { db in
            try JobRecord.filter(Column("batch_id") == batchID).order(Column("sequence")).fetchAll(db)
        }
        
        #expect(recoveredJobs.count == 2)
        // fetching -> queued, transcribing -> fetched
        #expect(recoveredJobs[0].state == JobState.queued.rawValue)
        #expect(recoveredJobs[1].state == JobState.fetched.rawValue)
    }
    
    @Test("Partial failure batch assembly and error reporting")
    func testPartialFailureBatchAssembly() async throws {
        let appDb = try AppDatabase.makeInMemory()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let writer = OutputWriter(customOutputDirectory: tempDir)
        
        let batchID = "BATCH-PARTIAL-FAIL"
        let batch = BatchRecord(id: batchID, expectedCount: 3, state: .active, language: "en")
        
        let job1 = JobRecord(
            id: "j1",
            batchID: batchID,
            sequence: 1,
            sourceURL: "https://www.youtube.com/watch?v=aaaaa111111",
            title: "Successful Chapter 1",
            creator: "Author A",
            durationSec: 120,
            state: .completed
        )
        
        let job2 = JobRecord(
            id: "j2",
            batchID: batchID,
            sequence: 2,
            sourceURL: "https://www.youtube.com/watch?v=bbbbb222222",
            title: "Private / Restricted Video",
            creator: "Author B",
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
            title: "Successful Chapter 2",
            creator: "Author A",
            durationSec: 180,
            state: .completed
        )
        
        try await appDb.dbQueue.write { db in
            try batch.insert(db)
            try job1.insert(db)
            try job2.insert(db)
            try job3.insert(db)
            
            // Completed transcript records
            try TranscriptSectionRecord(
                jobID: "j1",
                text: "This is the transcript content of chapter one."
            ).insert(db)
            
            try TranscriptSectionRecord(
                jobID: "j3",
                text: "This is the transcript content of chapter three."
            ).insert(db)
        }
        
        let assembler = BatchAssembler(database: appDb, outputWriter: writer)
        let result = try assembler.assembleBatch(batchID: batchID)
        
        switch result {
        case .assembled(let fileURL, let isPartial):
            #expect(isPartial == true, "isPartial should be true when 1 of 3 videos failed")
            #expect(FileManager.default.fileExists(atPath: fileURL.path))
            
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            
            // Successful sections must be present in content
            #expect(content.contains("Successful Chapter 1"))
            #expect(content.contains("This is the transcript content of chapter one."))
            #expect(content.contains("Successful Chapter 2"))
            #expect(content.contains("This is the transcript content of chapter three."))
            
            // Failed video reason must be reported
            #expect(content.contains("Failed: 1"))
            #expect(content.contains("STATUS: İŞLENEMEDİ — HTTP 403: Forbidden"))
            
        default:
            Issue.record("Expected .assembled outcome was not received")
        }
    }
}
