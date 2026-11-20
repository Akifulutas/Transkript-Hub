import Foundation
import CryptoKit
import GRDB

public struct CachedTranscript: Sendable {
    public let id: String
    public let externalID: String?
    public let title: String
    public let durationSec: Double?
    public let sourcePath: String?
    public let outputPath: String?
    public let contentHash: String?
    public let modelID: String?
    public let languageCode: String?
    public let transcriptText: String
    public let createdAt: Date
    
    public init(
        id: String = UUID().uuidString,
        externalID: String? = nil,
        title: String,
        durationSec: Double? = nil,
        sourcePath: String? = nil,
        outputPath: String? = nil,
        contentHash: String? = nil,
        modelID: String? = nil,
        languageCode: String? = nil,
        transcriptText: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.externalID = externalID
        self.title = title
        self.durationSec = durationSec
        self.sourcePath = sourcePath
        self.outputPath = outputPath
        self.contentHash = contentHash
        self.modelID = modelID
        self.languageCode = languageCode
        self.transcriptText = transcriptText
        self.createdAt = createdAt
    }
}

public actor TranscriptCacheManager {
    private let database: AppDatabase
    
    public init(database: AppDatabase) {
        self.database = database
    }
    
    /// Computes a fast O(1) partial SHA-256 fingerprint (first 64 KB + middle 64 KB + last 64 KB + file size)
    /// for local files so identical audio files match deterministically while distinct files with the same name never collide.
    public nonisolated static func computeFastContentHash(forPath path: String?) -> String? {
        guard let path = path, !path.isEmpty,
              FileManager.default.fileExists(atPath: path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let fileSize = attrs[.size] as? UInt64, fileSize > 0,
              let handle = FileHandle(forReadingAtPath: path) else {
            return nil
        }
        defer { try? handle.close() }
        
        var hasher = SHA256()
        var sizeLE = fileSize.littleEndian
        withUnsafeBytes(of: &sizeLE) { hasher.update(bufferPointer: $0) }
        
        let chunkSize = 65536
        if fileSize <= UInt64(chunkSize * 3) {
            if let data = try? handle.readToEnd() {
                hasher.update(data: data)
            }
        } else {
            if let head = try? handle.read(upToCount: chunkSize) {
                hasher.update(data: head)
            }
            let midOffset = (fileSize / 2) - UInt64(chunkSize / 2)
            try? handle.seek(toOffset: midOffset)
            if let mid = try? handle.read(upToCount: chunkSize) {
                hasher.update(data: mid)
            }
            let tailOffset = fileSize - UInt64(chunkSize)
            try? handle.seek(toOffset: tailOffset)
            if let tail = try? handle.read(upToCount: chunkSize) {
                hasher.update(data: tail)
            }
        }
        
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    private nonisolated static func isModelAndLanguageCompatible(
        row: Row,
        requestedModel: String?,
        requestedLanguage: String?
    ) -> Bool {
        if let reqModel = requestedModel?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !reqModel.isEmpty,
           let rowModel = (row["model_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !rowModel.isEmpty,
           rowModel != reqModel {
            return false
        }
        if let reqLang = requestedLanguage?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !reqLang.isEmpty,
           reqLang != "auto",
           let rowLang = (row["language_code"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !rowLang.isEmpty,
           rowLang != "auto",
           rowLang != reqLang {
            return false
        }
        return true
    }
    
    /// Looks up an existing transcript without re-running transcription.
    /// Checks:
    /// 0. Content SHA-256 fingerprint match (when a local file exists at `sourcePath`)
    /// 1. Exact `externalID` (e.g. YouTube video ID or canonical path)
    /// 2. Audio duration (`±1.0s`) + exact title or exact filename match (eliminating bidirectional substring collisions)
    /// 3. Fallback search across existing history and completed jobs.
    public func findCached(
        title: String,
        durationSec: Double?,
        sourcePath: String? = nil,
        externalID: String? = nil,
        modelID: String? = nil,
        languageCode: String? = nil
    ) async -> CachedTranscript? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filename = sourcePath.map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() }
        let computedHash = Self.computeFastContentHash(forPath: sourcePath)
        
        do {
            return try await database.dbQueue.read { db -> CachedTranscript? in
                // 0. Direct query by content_hash if local file exists
                if let hash = computedHash {
                    let rows = try Row.fetchAll(
                        db,
                        sql: "SELECT * FROM transcript_cache WHERE content_hash = ? ORDER BY created_at DESC, rowid DESC",
                        arguments: [hash]
                    )
                    for row in rows {
                        if Self.isModelAndLanguageCompatible(row: row, requestedModel: modelID, requestedLanguage: languageCode),
                           let cached = self.makeCachedFromRow(row) {
                            return cached
                        }
                    }
                }
                
                // 1. Direct query in transcript_cache by externalID
                if let extID = externalID, !extID.isEmpty {
                    let rows = try Row.fetchAll(
                        db,
                        sql: "SELECT * FROM transcript_cache WHERE external_id = ? ORDER BY created_at DESC, rowid DESC",
                        arguments: [extID]
                    )
                    for row in rows {
                        if let hash = computedHash,
                           let rowHash = row["content_hash"] as? String,
                           !rowHash.isEmpty,
                           rowHash != hash {
                            continue
                        }
                        if Self.isModelAndLanguageCompatible(row: row, requestedModel: modelID, requestedLanguage: languageCode),
                           let cached = self.makeCachedFromRow(row) {
                            return cached
                        }
                    }
                }
                
                // 2. Query in transcript_cache by Duration + Exact Title / Exact Filename
                if let duration = durationSec, duration > 0 {
                    let minDur = duration - 1.0
                    let maxDur = duration + 1.0
                    let rows = try Row.fetchAll(
                        db,
                        sql: "SELECT * FROM transcript_cache WHERE duration_sec BETWEEN ? AND ? ORDER BY created_at DESC, rowid DESC",
                        arguments: [minDur, maxDur]
                    )
                    for row in rows {
                        if let hash = computedHash,
                           let rowHash = row["content_hash"] as? String,
                           !rowHash.isEmpty,
                           rowHash != hash {
                            continue
                        }
                        guard Self.isModelAndLanguageCompatible(row: row, requestedModel: modelID, requestedLanguage: languageCode) else {
                            continue
                        }
                        let rowTitle = (row["title"] as? String ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased()
                        let rowSource = (row["source_path"] as? String ?? "").lowercased()
                        let rowFilename = rowSource.isEmpty ? "" : URL(fileURLWithPath: rowSource).lastPathComponent.lowercased()
                        
                        let isExactTitleMatch = !cleanTitle.isEmpty && rowTitle == cleanTitle
                        let isExactFilenameMatch = filename != nil && !filename!.isEmpty && rowFilename == filename!
                        
                        if isExactTitleMatch || isExactFilenameMatch {
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
                
                // 4. Fallback: Search completed jobs by duration and exact title / filename
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
                        let jTitle = (row["title"] as? String ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased()
                        let jSource = (row["source_path"] as? String ?? "").lowercased()
                        let jFilename = jSource.isEmpty ? "" : URL(fileURLWithPath: jSource).lastPathComponent.lowercased()
                        
                        let isExactTitleMatch = !cleanTitle.isEmpty && jTitle == cleanTitle
                        let isExactFilenameMatch = filename != nil && !filename!.isEmpty && jFilename == filename!
                        
                        if isExactTitleMatch || isExactFilenameMatch {
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
        contentHash: String? = nil,
        modelID: String? = nil,
        languageCode: String? = nil,
        transcriptText: String
    ) async {
        guard !transcriptText.isEmpty else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        let id = UUID().uuidString
        let resolvedHash = contentHash ?? Self.computeFastContentHash(forPath: sourcePath)
        let resolvedFileSize: Int64?
        if let explicitSize = fileSize {
            resolvedFileSize = explicitSize
        } else if let path = sourcePath,
                  let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let s = attrs[.size] as? Int64 {
            resolvedFileSize = s
        } else {
            resolvedFileSize = nil
        }
        
        do {
            try await database.dbQueue.write { db in
                if let ext = externalID, !ext.isEmpty {
                    if let mod = modelID, !mod.isEmpty {
                        try db.execute(
                            sql: "DELETE FROM transcript_cache WHERE external_id = ? AND (model_id = ? OR model_id IS NULL)",
                            arguments: [ext, mod]
                        )
                    } else {
                        try db.execute(sql: "DELETE FROM transcript_cache WHERE external_id = ?", arguments: [ext])
                    }
                }
                try db.execute(
                    sql: """
                    INSERT INTO transcript_cache
                    (id, external_id, title, duration_sec, file_size, source_path, output_path, content_hash, model_id, language_code, transcript_text, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        id,
                        externalID,
                        title,
                        durationSec,
                        resolvedFileSize,
                        sourcePath,
                        outputPath,
                        resolvedHash,
                        modelID,
                        languageCode,
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
                    contentHash: row["content_hash"],
                    modelID: row["model_id"],
                    languageCode: row["language_code"],
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
            contentHash: row["content_hash"],
            modelID: row["model_id"],
            languageCode: row["language_code"],
            transcriptText: text,
            createdAt: ISO8601DateFormatter().date(from: row["created_at"] ?? "") ?? Date()
        )
    }
}
