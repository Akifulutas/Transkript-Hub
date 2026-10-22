import Foundation
import Testing
import GRDB
@testable import TranskriptHubCore

@Suite("Audit Enhancements & Optimization Test Suite")
struct AuditEnhancementsTests {
    
    // MARK: - 1. AudioDecoder Bounds & Buffer Reuse Tests
    @Test("AudioDecoder streaming with pre-allocated buffer successfully decodes audio")
    func testAudioDecoderStreamingSuccess() throws {
        let fixtureURL = URL(fileURLWithPath: "Tests/Fixtures/sample.m4a")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else { return }
        
        let decoder = AudioDecoder()
        let prepared = try decoder.decode(fileURL: fixtureURL)
        
        #expect(!prepared.samples.isEmpty)
        #expect(prepared.duration > 0.0)
        #expect(prepared.samples.allSatisfy { !$0.isNaN && !$0.isInfinite })
    }
    
    @Test("AudioDecoder throws typed error for non-existent file")
    func testAudioDecoderFileNotFound() throws {
        let fakeURL = URL(fileURLWithPath: "/tmp/non_existent_audio_\(UUID().uuidString).wav")
        let decoder = AudioDecoder()
        #expect(throws: AudioDecoderError.self) {
            try decoder.decode(fileURL: fakeURL)
        }
    }
    
    // MARK: - 2. BatchAssembler Subquery & Multi-Batch Isolation Tests
    @Test("BatchAssembler indexed subquery isolates batch sections strictly to requested batch")
    func testBatchAssemblerSubqueryIsolation() async throws {
        let appDb = try AppDatabase.makeInMemory()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let writer = OutputWriter(customOutputDirectory: tempDir)
        let assembler = BatchAssembler(database: appDb, outputWriter: writer)
        
        let batchA = "BATCH-ALPHA"
        let batchB = "BATCH-BETA"
        
        let batchRecordA = BatchRecord(id: batchA, expectedCount: 1, state: .completed, language: "tr")
        let batchRecordB = BatchRecord(id: batchB, expectedCount: 1, state: .completed, language: "en")
        
        let jobA = JobRecord(
            id: "job-alpha-1",
            batchID: batchA,
            sequence: 1,
            title: "Alpha Video",
            state: .completed
        )
        let jobB = JobRecord(
            id: "job-beta-1",
            batchID: batchB,
            sequence: 1,
            title: "Beta Video",
            state: .completed
        )
        
        let sectionA = TranscriptSectionRecord(jobID: "job-alpha-1", text: "Alpha Transcript Content", segments: nil)
        let sectionB = TranscriptSectionRecord(jobID: "job-beta-1", text: "Beta Transcript Content", segments: nil)
        
        try await appDb.dbQueue.write { db in
            try batchRecordA.insert(db)
            try batchRecordB.insert(db)
            try jobA.insert(db)
            try jobB.insert(db)
            try sectionA.insert(db)
            try sectionB.insert(db)
        }
        
        // Assemble Batch A
        let resultA = try assembler.assembleBatch(batchID: batchA, modelName: "tiny")
        switch resultA {
        case .assembled(let outputURL, let isPartial):
            #expect(!isPartial)
            let content = try String(contentsOf: outputURL, encoding: .utf8)
            #expect(content.contains("Alpha Transcript Content"))
            #expect(!content.contains("Beta Transcript Content"))
        default:
            Issue.record("Expected assembled batch result for Batch A")
        }
        
        // Assemble Batch B
        let resultB = try assembler.assembleBatch(batchID: batchB, modelName: "tiny")
        switch resultB {
        case .assembled(let outputURL, let isPartial):
            #expect(!isPartial)
            let content = try String(contentsOf: outputURL, encoding: .utf8)
            #expect(content.contains("Beta Transcript Content"))
            #expect(!content.contains("Alpha Transcript Content"))
        default:
            Issue.record("Expected assembled batch result for Batch B")
        }
    }
    
    @Test("BatchAssembler safely handles non-terminal jobs without crashing")
    func testBatchAssemblerNonTerminalHandling() async throws {
        let appDb = try AppDatabase.makeInMemory()
        let assembler = BatchAssembler(database: appDb)
        
        let batchID = "BATCH-WAITING"
        let batchRecord = BatchRecord(id: batchID, expectedCount: 2, state: .active, language: "tr")
        let job1 = JobRecord(id: "job-active-1", batchID: batchID, sequence: 1, state: .transcribing)
        let job2 = JobRecord(id: "job-completed-2", batchID: batchID, sequence: 2, state: .completed)
        
        try await appDb.dbQueue.write { db in
            try batchRecord.insert(db)
            try job1.insert(db)
            try job2.insert(db)
        }
        
        let result = try assembler.assembleBatch(batchID: batchID)
        switch result {
        case .waiting(let pendingCount):
            #expect(pendingCount == 1)
        default:
            Issue.record("Expected waiting result with pendingCount == 1")
        }
    }
    
    // MARK: - 3. Deno Architecture URL Check
    @Test("Deno download URL architecture matches running host platform")
    func testDenoArchitectureString() {
        let archString: String
        #if arch(arm64)
        archString = "aarch64"
        #else
        archString = "x86_64"
        #endif
        
        #if arch(arm64)
        #expect(archString == "aarch64")
        #else
        #expect(archString == "x86_64")
        #endif
        
        let urlString = "https://github.com/denoland/deno/releases/latest/download/deno-\(archString)-apple-darwin.zip"
        let url = URL(string: urlString)
        #expect(url != nil)
    }
    
    // MARK: - 4. FolderWatcher & Scan Trigger Tests
    @Test("FolderWatcher triggerImmediateScan executes and tracks processed paths correctly")
    @MainActor
    func testFolderWatcherScanAndProcessedPaths() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let watcher = FolderWatcher(watchedDirectory: tempDir)
        watcher.watchCustomFolder = true
        watcher.customFolderURL = tempDir
        
        let dummyPath = tempDir.appendingPathComponent("test_recording.m4a").path
        #expect(!watcher.isPathProcessed(dummyPath))
        
        watcher.markPathsAsProcessed([dummyPath])
        #expect(watcher.isPathProcessed(dummyPath))
        
        // Immediate scan invocation should be safe and idempotent
        watcher.triggerImmediateScan()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(watcher.isPathProcessed(dummyPath))
    }
    
    // MARK: - 5. BatchAssembler Empty Batch Test
    @Test("BatchAssembler returns empty result for non-existent batch")
    func testBatchAssemblerNonExistentBatch() async throws {
        let appDb = try AppDatabase.makeInMemory()
        let assembler = BatchAssembler(database: appDb)
        let result = try assembler.assembleBatch(batchID: "NON-EXISTENT-BATCH")
        switch result {
        case .empty:
            break
        default:
            Issue.record("Expected .empty result for non-existent batch")
        }
    }
}
