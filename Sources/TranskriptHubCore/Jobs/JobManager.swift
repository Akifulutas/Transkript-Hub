import Foundation
import GRDB

public actor JobManager {
    public let database: AppDatabase
    private let toolManager: ToolManager
    private let modelManager: ModelManager
    private let outputWriter: OutputWriter
    private let assembler: BatchAssembler
    private let cleanupManager: CleanupManager
    
    public init(
        database: AppDatabase,
        toolManager: ToolManager = ToolManager(),
        modelManager: ModelManager = ModelManager(),
        outputWriter: OutputWriter = OutputWriter()
    ) {
        self.database = database
        self.toolManager = toolManager
        self.modelManager = modelManager
        self.outputWriter = outputWriter
        self.assembler = BatchAssembler(database: database, outputWriter: outputWriter)
        self.cleanupManager = CleanupManager(database: database)
    }
    
    /// Creates a new batch with a sequence of YouTube URLs.
    public func createYouTubeBatch(urls: [String], language: String? = nil) async throws -> BatchRecord {
        let batchID = UUID().uuidString
        let batch = BatchRecord(
            id: batchID,
            kind: .youtube,
            expectedCount: urls.count,
            state: .active,
            language: language
        )
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let baseJobsDir = appSupport.appendingPathComponent("TranskriptHub/Jobs", isDirectory: true)
        
        try await database.dbQueue.write { db in
            try batch.insert(db)
            
            for (index, urlStr) in urls.enumerated() {
                let sequence = index + 1
                let jobID = UUID().uuidString
                let workspace = baseJobsDir.appendingPathComponent(jobID, isDirectory: true).path
                let parsed = URLParser.parseSingle(urlStr)
                
                let job = JobRecord(
                    id: jobID,
                    batchID: batchID,
                    sequence: sequence,
                    sourceType: "youtube",
                    sourceURL: parsed?.canonicalURL ?? urlStr,
                    externalID: parsed?.videoID,
                    state: .queued,
                    workspacePath: workspace
                )
                try job.insert(db)
            }
        }
        
        return batch
    }
    
    /// Startup recovery according to specification §6.
    public func recoverState() async throws {
        try await database.dbQueue.write { db in
            // 1. Reset fetching -> queued
            try db.execute(sql: "UPDATE job SET state = 'queued' WHERE state = 'fetching'")
            
            // 2. Reset transcribing -> fetched (audio is kept, only re-transcribe)
            try db.execute(sql: "UPDATE job SET state = 'fetched' WHERE state = 'transcribing'")
        }
        Log.info("Veritabanı kurtarma kontrolü tamamlandı.")
    }
    
    /// Processes an entire batch with resilient failure handling (22/25 partial assembly).
    public func processBatch(
        batchID: String,
        model: WhisperModel = .tiny,
        onJobUpdate: (@Sendable (JobRecord) -> Void)? = nil
    ) async throws -> AssemblyResult {
        try await toolManager.ensureToolsReady()
        
        let modelURL: URL
        if !modelManager.isModelDownloaded(model) {
            modelURL = try await modelManager.downloadModel(model)
        } else {
            modelURL = modelManager.localURL(for: model)
        }
        
        let whisperEngine = try WhisperCppEngine(modelPath: modelURL.path)
        let audioDecoder = AudioDecoder()
        let ytdlp = YTDLPClient(toolManager: toolManager)
        let postProcessor = TranscriptPostProcessor()
        
        // Fetch jobs for batch
        let jobs = try await database.dbQueue.read { db -> [JobRecord] in
            try JobRecord.filter(Column("batch_id") == batchID).order(Column("sequence")).fetchAll(db)
        }
        
        for job in jobs {
            guard !JobState(rawValue: job.state)!.isTerminal else { continue }
            
            var currentJob = job
            let workspaceURL = URL(fileURLWithPath: job.workspacePath ?? "/tmp/\(job.id)")
            
            // Step 1: Fetching
            if currentJob.state == JobState.queued.rawValue {
                try await updateJobState(jobID: currentJob.id, state: .fetching)
                currentJob.state = JobState.fetching.rawValue
                onJobUpdate?(currentJob)
                
                do {
                    guard let url = currentJob.sourceURL else {
                        throw YTDLPError(kind: .videoUnavailable, message: "Kaynak URL eksik")
                    }
                    
                    let media = try await ytdlp.fetch(url: url, into: workspaceURL)
                    
                    let jobID = currentJob.id
                    let title = media.metadata.title
                    let creator = media.metadata.channel
                    let duration = media.metadata.duration
                    let sourcePath = media.localAudioURL.path
                    let now = ISO8601DateFormatter().string(from: Date())
                    
                    try await database.dbQueue.write { db in
                        try db.execute(
                            sql: """
                            UPDATE job SET 
                                state = 'fetched', 
                                title = ?, 
                                creator = ?, 
                                duration_sec = ?, 
                                source_path = ?,
                                updated_at = ?
                            WHERE id = ?
                            """,
                            arguments: [title, creator, duration, sourcePath, now, jobID]
                        )
                    }
                    currentJob.state = JobState.fetched.rawValue
                    currentJob.title = title
                    currentJob.creator = creator
                    currentJob.durationSec = duration
                    currentJob.sourcePath = sourcePath
                    onJobUpdate?(currentJob)
                    
                } catch {
                    Log.error("Video indirme hatası (\(currentJob.sequence)): \(error.localizedDescription)")
                    try await markJobFailed(jobID: currentJob.id, error: error)
                    currentJob.state = JobState.failed.rawValue
                    currentJob.errorMessage = error.localizedDescription
                    onJobUpdate?(currentJob)
                    continue // Do NOT halt batch; proceed to next video!
                }
            }
            
            // Step 2: Transcribing
            if currentJob.state == JobState.fetched.rawValue {
                try await updateJobState(jobID: currentJob.id, state: .transcribing)
                currentJob.state = JobState.transcribing.rawValue
                onJobUpdate?(currentJob)
                
                do {
                    guard let sourcePath = currentJob.sourcePath, FileManager.default.fileExists(atPath: sourcePath) else {
                        throw AudioDecoderError.fileNotFound(URL(fileURLWithPath: currentJob.sourcePath ?? ""))
                    }
                    
                    let prepared = try audioDecoder.decode(fileURL: URL(fileURLWithPath: sourcePath))
                    let result = try await whisperEngine.transcribe(prepared, options: TranscriptionOptions())
                    let formatted = postProcessor.process(segments: result.segments)
                    
                    let jobID = currentJob.id
                    let detectedLang = result.detectedLanguage
                    let now = ISO8601DateFormatter().string(from: Date())
                    
                    try await database.dbQueue.write { db in
                        let section = TranscriptSectionRecord(jobID: jobID, text: formatted)
                        try section.insert(db)
                        
                        try db.execute(
                            sql: "UPDATE job SET state = 'completed', detected_lang = ?, updated_at = ? WHERE id = ?",
                            arguments: [detectedLang, now, jobID]
                        )
                    }
                    
                    currentJob.state = JobState.completed.rawValue
                    currentJob.detectedLang = detectedLang
                    onJobUpdate?(currentJob)
                    
                } catch {
                    Log.error("Transkripsiyon hatası (\(currentJob.sequence)): \(error.localizedDescription)")
                    try await markJobFailed(jobID: currentJob.id, error: error)
                    currentJob.state = JobState.failed.rawValue
                    currentJob.errorMessage = error.localizedDescription
                    onJobUpdate?(currentJob)
                    continue // Do NOT halt batch!
                }
            }
        }
        
        // Final Assembly & Cleanup
        let result = try assembler.assembleBatch(batchID: batchID, modelName: model.rawValue)
        try cleanupManager.cleanupBatch(batchID: batchID)
        return result
    }
    
    private func updateJobState(jobID: String, state: JobState) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let stateStr = state.rawValue
        try await database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE job SET state = ?, updated_at = ? WHERE id = ?",
                arguments: [stateStr, now, jobID]
            )
        }
    }
    
    private func markJobFailed(jobID: String, error: Error) async throws {
        let msg = error.localizedDescription
        let kind: String
        if let ytErr = error as? YTDLPError {
            kind = ytErr.kind.rawValue
        } else {
            kind = "unknown"
        }
        let now = ISO8601DateFormatter().string(from: Date())
        
        try await database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE job SET state = 'failed', error_kind = ?, error_message = ?, updated_at = ? WHERE id = ?",
                arguments: [kind, msg, now, jobID]
            )
        }
    }
}
