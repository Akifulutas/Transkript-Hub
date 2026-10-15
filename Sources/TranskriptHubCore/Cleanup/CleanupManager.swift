import Foundation
import GRDB

public final class CleanupManager: Sendable {
    private let database: AppDatabase
    
    public init(database: AppDatabase) {
        self.database = database
    }
    
    public func cleanupBatch(batchID: String) throws {
        // 1. Fetch job workspace paths
        let workspacePaths = try database.dbQueue.read { db -> [String] in
            let jobs = try JobRecord.filter(Column("batch_id") == batchID).fetchAll(db)
            return jobs.compactMap(\.workspacePath)
        }
        
        // 2. Delete workspace directories from disk
        let fm = FileManager.default
        for path in workspacePaths {
            if fm.fileExists(atPath: path) {
                try? fm.removeItem(atPath: path)
            }
        }
        
        // 3. Mark batch as cleaned in DB and clean transcript sections
        let now = ISO8601DateFormatter().string(from: Date())
        try database.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM transcript_section WHERE job_id IN (SELECT id FROM job WHERE batch_id = ?)", arguments: [batchID])
            try db.execute(sql: "UPDATE batch SET cleaned_at = ? WHERE id = ?", arguments: [now, batchID])
        }
        
        Log.info("Batch cleanup completed: \(batchID) (Temporary audio files removed).")
    }
}
