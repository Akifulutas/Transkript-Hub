import Foundation
import Testing
import GRDB
@testable import TranskriptHubCore

@Suite("Zero-Regression E2E Integration Test Suite")
struct ZeroRegressionE2ETests {
    
    @Test("URLParser regression check: extracts, validates, and deduplicates YouTube links")
    func testURLParserRegressionCheck() {
        let dirtyInput = """
        İnceleme videoları listesi:
        1. https://www.youtube.com/watch?v=dQw4w9WgXcQ
        2. https://youtu.be/dQw4w9WgXcQ (Tekrarlanan link)
        3. https://youtube.com/shorts/5O3eU_0z7b0
        4. https://www.youtube.com/playlist?list=PL1234567890abcdef
        5. https://vimeo.com/123456789 (Desteklenmeyen)
        6. https://example.com/invalid
        """
        
        let extractedVideos = URLParser.parseBulk(dirtyInput)
        #expect(extractedVideos.count == 2, "Only supported distinct YouTube video IDs should be extracted via parseBulk")
        
        // Single parse check
        #expect(URLParser.parseSingle("https://www.youtube.com/watch?v=dQw4w9WgXcQ") != nil)
        #expect(URLParser.parseSingle("https://youtu.be/5O3eU_0z7b0") != nil)
        #expect(URLParser.parseSingle("https://vimeo.com/12345") == nil)
        #expect(URLParser.parseSingle("not a url") == nil)
        
        // Detection check
        if case .playlist = URLParser.detectType("https://www.youtube.com/playlist?list=PL1234567890abcdef") {
            // Expected
        } else {
            Issue.record("Expected playlist link type")
        }
        
        if case .singleVideo = URLParser.detectType("https://www.youtube.com/watch?v=dQw4w9WgXcQ") {
            // Expected
        } else {
            Issue.record("Expected singleVideo link type")
        }
    }
    
    @Test("AudioValidator regression check: verifies extension support and duration on sample")
    func testAudioValidatorRegressionCheck() throws {
        // Supported extensions
        let supported = ["m4a", "mp3", "wav", "aac", "caf", "aiff", "flac", "mp4", "mov", "mkv"]
        for ext in supported {
            #expect(AudioValidator.isExtensionSupported(ext) == true)
        }
        
        // Unsupported extensions
        let unsupported = ["txt", "pdf", "docx", "exe", "dmg", "zip", "iso"]
        for ext in unsupported {
            #expect(AudioValidator.isExtensionSupported(ext) == false)
        }
        
        // Sample file duration check if fixture exists
        let sampleURL = URL(fileURLWithPath: "Tests/Fixtures/sample.m4a")
        if FileManager.default.fileExists(atPath: sampleURL.path) {
            let duration = try AudioValidator.validate(fileURL: sampleURL)
            #expect(duration > 0.0)
        }
    }
    
    @Test("TranscriptPostProcessor regression check: strips noise tags and breaks repetition loops")
    func testPostProcessorRegressionCheck() {
        let processor = TranscriptPostProcessor()
        
        // Noise tags
        let noiseSegments = [
            Segment(start: 0.0, end: 1.0, text: "[Music] Merhaba arkadaşlar [APPLAUSE]"),
            Segment(start: 1.1, end: 2.5, text: "Bugünkü konumuz Apple Silicon (gülüşmeler)")
        ]
        let cleaned = processor.process(segments: noiseSegments)
        #expect(!cleaned.contains("[Music]"))
        #expect(!cleaned.contains("[APPLAUSE]"))
        #expect(!cleaned.contains("(gülüşmeler)"))
        #expect(cleaned.contains("Merhaba arkadaşlar"))
        #expect(cleaned.contains("Bugünkü konumuz Apple Silicon"))
        
        // Repetition loops
        let loopSegments = (0..<8).map { i in
            Segment(start: Double(i), end: Double(i + 1), text: "Lütfen abone olun.")
        } + [Segment(start: 8.0, end: 9.0, text: "Videoya devam ediyoruz.")]
        
        let loopCleaned = processor.process(segments: loopSegments)
        let count = loopCleaned.components(separatedBy: "Lütfen abone olun.").count - 1
        #expect(count <= 2, "Hallucinated repetition loops must be broken to at most 2 occurrences")
        #expect(loopCleaned.contains("Videoya devam ediyoruz."))
    }
    
    @Test("OutputWriter regression check: filename sanitization, sequential collisions, and safe truncation")
    func testOutputWriterRegressionCheck() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let writer = OutputWriter(customOutputDirectory: tempDir)
        
        // Sanitization
        let dirtyTitle = "Video // Adı: \"Harika Bir Gün\" <Test>? *"
        let sanitized = OutputWriter.sanitizeFilename(dirtyTitle)
        #expect(!sanitized.contains("/"))
        #expect(!sanitized.contains(":"))
        #expect(!sanitized.contains("\""))
        #expect(!sanitized.contains("?"))
        #expect(!sanitized.contains("*"))
        
        // Truncation <= 150 characters
        let veryLongTitle = String(repeating: "ÇokUzunVideoBaşlığı_", count: 20)
        let truncated = OutputWriter.sanitizeFilename(veryLongTitle)
        #expect(truncated.count <= 150)
        
        // Sequential collision numbering
        let url1 = writer.resolveUniqueURL(forBaseName: "Rapor", in: tempDir)
        #expect(url1.lastPathComponent == "Rapor.txt")
        try writer.write(content: "İlk metin", to: url1)
        
        let url2 = writer.resolveUniqueURL(forBaseName: "Rapor", in: tempDir)
        #expect(url2.lastPathComponent == "Rapor (2).txt")
        try writer.write(content: "İkinci metin", to: url2)
        
        let url3 = writer.resolveUniqueURL(forBaseName: "Rapor", in: tempDir)
        #expect(url3.lastPathComponent == "Rapor (3).txt")
        try writer.write(content: "Üçüncü metin", to: url3)
    }
    
    @Test("ModelManager regression check: verifies all whisper model filenames")
    func testModelManagerRegressionCheck() {
        let manager = ModelManager(modelsDirectory: URL(fileURLWithPath: "/tmp/models"))
        #expect(manager.localURL(for: .tiny).lastPathComponent == "ggml-tiny.bin")
        #expect(manager.localURL(for: .base).lastPathComponent == "ggml-base.bin")
        #expect(manager.localURL(for: .small).lastPathComponent == "ggml-small.bin")
        #expect(manager.localURL(for: .medium).lastPathComponent == "ggml-medium.bin")
        #expect(manager.localURL(for: .largeV3Turbo).lastPathComponent == "ggml-large-v3-turbo.bin")
        #expect(manager.localURL(for: .largeV3TurboQ5).lastPathComponent == "ggml-large-v3-turbo-q5_0.bin")
    }
    
    @Test("Full End-to-End pipeline pass: Ingestion -> Batch Creation -> Processing -> DB Persistence")
    func testFullEndToEndPipelinePass() async throws {
        let appDb = try AppDatabase.makeInMemory()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let writer = OutputWriter(customOutputDirectory: tempDir)
        let jobManager = JobManager(database: appDb, outputWriter: writer)
        
        let batch = try await jobManager.createYouTubeBatch(
            urls: ["https://www.youtube.com/watch?v=video123456"],
            language: "tr"
        )
        
        #expect(batch.expectedCount == 1)
        #expect(batch.state == BatchState.active.rawValue)
        
        // Fetch created job
        let jobs = try await appDb.dbQueue.read { db in
            try JobRecord.filter(Column("batch_id") == batch.id).fetchAll(db)
        }
        #expect(jobs.count == 1)
        let job = jobs[0]
        #expect(job.externalID == "video123456")
        
        // Simulate transcription output insertion
        let segments = [
            Segment(start: 0.0, end: 3.0, text: "Merhaba dünya"),
            Segment(start: 3.2, end: 6.0, text: "Transkript Hub başarıyla çalışıyor.")
        ]
        let postProcessor = TranscriptPostProcessor()
        let processedText = postProcessor.process(segments: segments)
        
        try await appDb.dbQueue.write { db in
            let section = TranscriptSectionRecord(jobID: job.id, text: processedText)
            try section.insert(db)
            
            try db.execute(sql: "UPDATE job SET state = 'completed' WHERE id = :id", arguments: ["id": job.id])
        }
        
        // Assemble batch
        let assembler = BatchAssembler(database: appDb, outputWriter: writer)
        let assemblyResult = try assembler.assembleBatch(batchID: batch.id, modelName: "tiny")
        
        switch assemblyResult {
        case .assembled(let outputURL, let isPartial):
            #expect(isPartial == false)
            #expect(FileManager.default.fileExists(atPath: outputURL.path))
            let content = try String(contentsOf: outputURL, encoding: .utf8)
            #expect(content.contains("Transkript Hub başarıyla çalışıyor."))
        default:
            Issue.record("Assembly failed to return .assembled")
        }
    }
}
