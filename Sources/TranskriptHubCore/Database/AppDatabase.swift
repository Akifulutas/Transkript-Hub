import Foundation
import GRDB

public final class AppDatabase: Sendable {
    public let dbQueue: DatabaseQueue
    
    public init(_ dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try migrator.migrate(dbQueue)
    }
    
    public static func makeInMemory() throws -> AppDatabase {
        var config = Configuration()
        config.qos = .userInitiated
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: config)
        return try AppDatabase(queue)
    }
    
    public static func makeShared(at path: String? = nil) throws -> AppDatabase {
        let dbPath: String
        if let custom = path {
            dbPath = custom
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dbDir = appSupport.appendingPathComponent("TranskriptHub/Database", isDirectory: true)
            try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
            dbPath = dbDir.appendingPathComponent("jobs.sqlite").path
        }
        
        var config = Configuration()
        config.qos = .userInitiated
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(path: dbPath, configuration: config)
        return try AppDatabase(queue)
    }
    
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = false
        #endif
        
        migrator.registerMigration("v1_initial_schema") { db in
            try db.create(table: "batch") { t in
                t.column("id", .text).primaryKey()
                t.column("created_at", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("expected_count", .integer).notNull()
                t.column("state", .text).notNull()
                t.column("language", .text)
                t.column("output_path", .text)
                t.column("cleaned_at", .text)
            }
            
            try db.create(table: "job") { t in
                t.column("id", .text).primaryKey()
                t.column("batch_id", .text).notNull().references("batch", onDelete: .cascade)
                t.column("sequence", .integer).notNull()
                t.column("source_type", .text).notNull()
                t.column("source_url", .text)
                t.column("source_path", .text)
                t.column("external_id", .text)
                t.column("title", .text)
                t.column("creator", .text)
                t.column("duration_sec", .double)
                t.column("state", .text).notNull()
                t.column("attempt", .integer).notNull().defaults(to: 0)
                t.column("next_attempt_at", .text)
                t.column("error_kind", .text)
                t.column("error_message", .text)
                t.column("workspace_path", .text)
                t.column("detected_lang", .text)
                t.column("updated_at", .text).notNull()
                
                t.uniqueKey(["batch_id", "sequence"])
                t.uniqueKey(["batch_id", "external_id"])
            }
            
            try db.create(table: "transcript_section") { t in
                t.column("job_id", .text).primaryKey().references("job", onDelete: .cascade)
                t.column("text", .text).notNull()
                t.column("segments", .text)
            }
            
            try db.create(table: "session_item") { t in
                t.column("id", .text).primaryKey()
                t.column("position", .integer).notNull()
                t.column("url", .text).notNull()
                t.column("external_id", .text).notNull().unique()
                t.column("title", .text)
                t.column("duration_sec", .double)
                t.column("added_at", .text).notNull()
            }
            
            try db.create(table: "history") { t in
                t.column("external_id", .text).primaryKey()
                t.column("title", .text)
                t.column("output_path", .text)
                t.column("done_at", .text).notNull()
            }
            
            try db.create(table: "watched_folder") { t in
                t.column("id", .text).primaryKey()
                t.column("path", .text).notNull().unique()
                t.column("enabled", .integer).notNull()
                t.column("extensions", .text).notNull()
                t.column("delete_original", .integer).notNull().defaults(to: 0)
            }
        }
        
        migrator.registerMigration("v2_transcript_cache") { db in
            try db.create(table: "transcript_cache") { t in
                t.column("id", .text).primaryKey()
                t.column("external_id", .text)
                t.column("title", .text).notNull()
                t.column("duration_sec", .double)
                t.column("file_size", .integer)
                t.column("source_path", .text)
                t.column("output_path", .text)
                t.column("transcript_text", .text).notNull()
                t.column("created_at", .text).notNull()
            }
            try db.create(index: "idx_cache_duration", on: "transcript_cache", columns: ["duration_sec"])
            try db.create(index: "idx_cache_title", on: "transcript_cache", columns: ["title"])
            try db.create(index: "idx_cache_external_id", on: "transcript_cache", columns: ["external_id"])
        }
        
        return migrator
    }
}

extension AppDatabase {
    /// Atomically updates the formatted transcript text and JSON-serialized segments for a given job.
    public func updateTranscript(jobId: String, newText: String, segments: [Segment]) async throws {
        let encoder = JSONEncoder()
        let segmentsData = try encoder.encode(segments)
        let segmentsString = String(data: segmentsData, encoding: .utf8)
        let now = ISO8601DateFormatter().string(from: Date())
        
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO transcript_section (job_id, text, segments)
                VALUES (?, ?, ?)
                ON CONFLICT(job_id) DO UPDATE SET
                    text = excluded.text,
                    segments = excluded.segments
                """,
                arguments: [jobId, newText, segmentsString]
            )
            
            try db.execute(
                sql: "UPDATE job SET updated_at = ? WHERE id = ?",
                arguments: [now, jobId]
            )
        }
    }
    
    /// Fetches the transcript text and decoded segments for a job.
    public func fetchTranscriptSection(jobId: String) async throws -> (text: String, segments: [Segment])? {
        try await dbQueue.read { db in
            guard let record = try TranscriptSectionRecord.fetchOne(
                db,
                sql: "SELECT * FROM transcript_section WHERE job_id = ?",
                arguments: [jobId]
            ) else {
                return nil
            }
            var parsedSegments: [Segment] = []
            if let jsonString = record.segments, let data = jsonString.data(using: .utf8) {
                parsedSegments = (try? JSONDecoder().decode([Segment].self, from: data)) ?? []
            }
            return (text: record.text, segments: parsedSegments)
        }
    }
}
