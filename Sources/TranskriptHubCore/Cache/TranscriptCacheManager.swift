import Foundation
import GRDB

public struct CachedTranscript: Sendable {
    public let id: String
    public let externalID: String?
    public let title: String
    public let durationSec: Double?
    public let sourcePath: String?
    public let outputPath: String?
    public let transcriptText: String
    public let createdAt: Date
    
    public init(
        id: String = UUID().uuidString,
        externalID: String? = nil,
        title: String,
        durationSec: Double? = nil,
        sourcePath: String? = nil,
        outputPath: String? = nil,
        transcriptText: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.externalID = externalID
        self.title = title
        self.durationSec = durationSec
        self.sourcePath = sourcePath
        self.outputPath = outputPath
        self.transcriptText = transcriptText
        self.createdAt = createdAt
    }
}

public actor TranscriptCacheManager {
    private let database: AppDatabase
    
    public init(database: AppDatabase) {
        self.database = database
    }
    
    /// Looks up an existing transcript without re-running transcription.
    /// Checks:
    /// 1. Exact externalID (e.g. YouTube video ID)
    /// 2. Audio duration (length) + title/filename matching within a 1.0 second tolerance
    /// 3. Fallback search across existing history and completed jobs.
    public func findCached(
        title: String,
        durationSec: Double?,
        sourcePath: String? = nil,
        externalID: String? = nil
    ) async -> CachedTranscript? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filename = sourcePath.map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() }
        
        do {
            return try await database.dbQueue.read { db -> CachedTranscript? in
                // 1. Direct query in transcript_cache by externalID
                if let extID = externalID, !extID.isEmpty {
                    let row = try Row.fetchOne(
                        db,
                        sql: "SELECT * FROM transcript_cache WHERE external_id = ? ORDER BY created_at DESC, rowid DESC LIMIT 1",
                        arguments: [extID]
                    )
                    if let row = row, let cached = self.makeCachedFromRow(row) {
                        return cached
                    }
                }
                
                // 2. Query in transcript_cache by Duration + Name
                if let duration = durationSec, duration > 0 {
                    let minDur = duration - 1.0
                    let maxDur = duration + 1.0
                    let rows = try Row.fetchAll(
                        db,
                        sql: "SELECT * FROM transcript_cache WHERE duration_sec BETWEEN ? AND ? ORDER BY created_at DESC, rowid DESC",
                        arguments: [minDur, maxDur]
                    )
                    for row in rows {
                        let rowTitle = (row["title"] as? String ?? "").lowercased()
                        let rowSource = (row["source_path"] as? String ?? "").lowercased()
                        if rowTitle == cleanTitle ||
                            rowTitle.contains(cleanTitle) ||
                            cleanTitle.contains(rowTitle) ||
                            (filename != nil && rowSource.hasSuffix(filename!)) {
                            if let cached = self.makeCachedFromRow(row) {
                                return cached
                            }
                        }
                    }
                }
                
                // 3. Fallback: Search in completed jobs and transcript_section
                if let extID = externalID, !extID.isEmpty {
                    let jobRow = try Row.fetchOne(
                        db,
                        sql: """
                        SELECT j.id, j.title, j.duration_sec, j.source_path, j.external_id, ts.text, b.output_path, j.updated_at
                        FROM job j
                        JOIN transcript_section ts ON j.id = ts.job_id
                        LEFT JOIN batch b ON j.batch_id = b.id
                        WHERE j.state = 'completed' AND (j.external_id = ? OR j.source_path = ?)
                        LIMIT 1
                        """,
                        arguments: [extID, extID]
                    )
                    if let row = jobRow, let text = row["text"] as? String, !text.isEmpty {
                        return CachedTranscript(
                            id: row["id"] ?? UUID().uuidString,
                            externalID: row["external_id"],
                            title: row["title"] ?? cleanTitle,
                            durationSec: row["duration_sec"],
                            sourcePath: row["source_path"],
                            outputPath: row["output_path"],
                            transcriptText: text,
                            createdAt: ISO8601DateFormatter().date(from: row["updated_at"] ?? "") ?? Date()
                        )
                    }
                }
                
                // 4. Fallback: Search completed jobs by duration and title
                if let duration = durationSec, duration > 0 {
                    let minDur = duration - 1.0
                    let maxDur = duration + 1.0
                    let jobRows = try Row.fetchAll(
                        db,
                        sql: """
                        SELECT j.id, j.title, j.duration_sec, j.source_path, j.external_id, ts.text, b.output_path, j.updated_at
                        FROM job j
                        JOIN transcript_section ts ON j.id = ts.job_id
                        LEFT JOIN batch b ON j.batch_id = b.id
                        WHERE j.state = 'completed' AND j.duration_sec BETWEEN ? AND ?
                        """,
                        arguments: [minDur, maxDur]
                    )
                    for row in jobRows {
                        let jTitle = (row["title"] as? String ?? "").lowercased()
                        if jTitle == cleanTitle || jTitle.contains(cleanTitle) || cleanTitle.contains(jTitle) {
                            if let text = row["text"] as? String, !text.isEmpty {
                                return CachedTranscript(
                                    id: row["id"] ?? UUID().uuidString,
                                    externalID: row["external_id"],
                                    title: row["title"] ?? cleanTitle,
                                    durationSec: row["duration_sec"],
                                    sourcePath: row["source_path"],
                                    outputPath: row["output_path"],
                                    transcriptText: text,
                                    createdAt: ISO8601DateFormatter().date(from: row["updated_at"] ?? "") ?? Date()
                                )
                            }
                        }
                    }
                }
                
                // 5. Fallback: Search history table (read file from disk if still present)
                if let extID = externalID, !extID.isEmpty {
                    let hRow = try Row.fetchOne(db, sql: "SELECT * FROM history WHERE external_id = ? LIMIT 1", arguments: [extID])
                    if let row = hRow, let path = row["output_path"] as? String, FileManager.default.fileExists(atPath: path),
                       let content = try? String(contentsOfFile: path, encoding: .utf8), !content.isEmpty {
                        return CachedTranscript(
                            id: extID,
                            externalID: extID,
                            title: row["title"] ?? cleanTitle,
                            durationSec: durationSec,
                            sourcePath: sourcePath,
                            outputPath: path,
                            transcriptText: content,
                            createdAt: ISO8601DateFormatter().date(from: row["done_at"] ?? "") ?? Date()
                        )
                    }
                }
                
                return nil
            }
        } catch {
            Log.error("Transcript cache lookup error: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Saves a newly generated transcript to the cache table for future instant re-use.
    public func save(
        externalID: String?,
        title: String,
        durationSec: Double?,
        fileSize: Int64? = nil,
        sourcePath: String? = nil,
        outputPath: String?,
        transcriptText: String
    ) async {
        guard !transcriptText.isEmpty else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        let id = UUID().uuidString
        
        do {
            try await database.dbQueue.write { db in
                if let ext = externalID, !ext.isEmpty {
                    try db.execute(sql: "DELETE FROM transcript_cache WHERE external_id = ?", arguments: [ext])
                }
                try db.execute(
                    sql: """
                    INSERT INTO transcript_cache
                    (id, external_id, title, duration_sec, file_size, source_path, output_path, transcript_text, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        id,
                        externalID,
                        title,
                        durationSec,
                        fileSize,
                        sourcePath,
                        outputPath,
                        transcriptText,
                        now
                    ]
                )
            }
        } catch {
            Log.error("Transcript cache save error: \(error.localizedDescription)")
        }
    }
    
    private nonisolated func makeCachedFromRow(_ row: Row) -> CachedTranscript? {
        guard let text = row["transcript_text"] as? String, !text.isEmpty else {
            // If text is not stored, try reading from output_path
            if let path = row["output_path"] as? String, FileManager.default.fileExists(atPath: path),
               let fileContent = try? String(contentsOfFile: path, encoding: .utf8), !fileContent.isEmpty {
                return CachedTranscript(
                    id: row["id"] ?? UUID().uuidString,
                    externalID: row["external_id"],
                    title: row["title"] ?? "",
                    durationSec: row["duration_sec"],
                    sourcePath: row["source_path"],
                    outputPath: path,
                    transcriptText: fileContent,
                    createdAt: ISO8601DateFormatter().date(from: row["created_at"] ?? "") ?? Date()
                )
            }
            return nil
        }
        
        return CachedTranscript(
            id: row["id"] ?? UUID().uuidString,
            externalID: row["external_id"],
            title: row["title"] ?? "",
            durationSec: row["duration_sec"],
            sourcePath: row["source_path"],
            outputPath: row["output_path"],
            transcriptText: text,
            createdAt: ISO8601DateFormatter().date(from: row["created_at"] ?? "") ?? Date()
        )
    }
}
