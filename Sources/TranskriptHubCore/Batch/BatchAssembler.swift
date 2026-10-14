import Foundation
import GRDB

public enum AssemblyResult: Sendable {
    case waiting(pendingCount: Int)
    case assembled(outputURL: URL, isPartial: Bool)
    case empty
}

public final class BatchAssembler: Sendable {
    private let database: AppDatabase
    private let outputWriter: OutputWriter
    
    public init(database: AppDatabase, outputWriter: OutputWriter = OutputWriter()) {
        self.database = database
        self.outputWriter = outputWriter
    }
    
    public func assembleBatch(batchID: String, modelName: String = "tiny") throws -> AssemblyResult {
        let (batch, jobs, sections) = try database.dbQueue.read { db -> (BatchRecord?, [JobRecord], [String: TranscriptSectionRecord]) in
            let b = try BatchRecord.fetchOne(db, key: batchID)
            let j = try JobRecord.filter(Column("batch_id") == batchID).order(Column("sequence")).fetchAll(db)
            let sList = try TranscriptSectionRecord.fetchAll(db)
            var sMap: [String: TranscriptSectionRecord] = [:]
            for s in sList {
                sMap[s.jobID] = s
            }
            return (b, j, sMap)
        }
        
        guard let batch = batch, !jobs.isEmpty else {
            return .empty
        }
        
        // Check if all jobs are terminal
        let nonTerminal = jobs.filter { !JobState(rawValue: $0.state)!.isTerminal }
        if !nonTerminal.isEmpty {
            return .waiting(pendingCount: nonTerminal.count)
        }
        
        // Assemble sections
        var items: [BatchItemSection] = []
        var completedCount = 0
        var failedCount = 0
        
        for job in jobs {
            let section = sections[job.id]
            let isFailed = (job.state == JobState.failed.rawValue || job.state == JobState.cancelled.rawValue)
            
            if isFailed {
                failedCount += 1
                items.append(BatchItemSection(
                    sequence: job.sequence,
                    totalCount: batch.expectedCount,
                    title: job.title,
                    channel: job.creator,
                    durationSec: job.durationSec,
                    url: job.sourceURL,
                    localFilePath: job.sourcePath,
                    language: nil,
                    transcriptText: nil,
                    errorMessage: job.errorMessage ?? "Bilinmeyen hata",
                    isYouTube: job.sourceType == "youtube"
                ))
            } else {
                completedCount += 1
                items.append(BatchItemSection(
                    sequence: job.sequence,
                    totalCount: batch.expectedCount,
                    title: job.title,
                    channel: job.creator,
                    durationSec: job.durationSec,
                    url: job.sourceURL,
                    localFilePath: job.sourcePath,
                    language: job.detectedLang ?? batch.language,
                    transcriptText: section?.text ?? "",
                    errorMessage: nil,
                    isYouTube: job.sourceType == "youtube"
                ))
            }
        }
        
        let metadata = BatchExportMetadata(
            batchID: batch.id,
            sourceType: batch.kind == "youtube" ? "YouTube" : "Audio Files",
            createdAt: ISO8601DateFormatter().date(from: batch.createdAt) ?? Date(),
            totalCount: batch.expectedCount,
            completedCount: completedCount,
            failedCount: failedCount,
            modelName: modelName,
            language: batch.language ?? "auto"
        )
        
        let formattedText = OutputFormatter.formatBatch(metadata: metadata, items: items)
        
        // File Name:
        // If single video: <Title>.txt (or sanitized title)
        // If multiple videos: YouTube - <N> of <Total> Video - <YYYY-MM-DD>.txt
        let baseFileName: String
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        
        if batch.expectedCount == 1, let firstTitle = jobs.first?.title, !firstTitle.isEmpty {
            baseFileName = firstTitle
        } else {
            let prefix = batch.kind == "youtube" ? "YouTube" : "Ses"
            if failedCount > 0 {
                baseFileName = "\(prefix) - \(completedCount) of \(batch.expectedCount) Video - \(dateStr) [PARTIAL]"
            } else {
                baseFileName = "\(prefix) - \(batch.expectedCount) Video - \(dateStr)"
            }
        }
        
        let targetURL = outputWriter.resolveUniqueURL(forBaseName: baseFileName, in: outputWriter.defaultOutputDirectory)
        try outputWriter.write(content: formattedText, to: targetURL)
        
        // Update batch state in DB
        let finalState: BatchState = (failedCount > 0) ? .completedWithErrors : .completed
        try database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE batch SET state = ?, output_path = ? WHERE id = ?",
                arguments: [finalState.rawValue, targetURL.path, batch.id]
            )
        }
        
        return .assembled(outputURL: targetURL, isPartial: failedCount > 0)
    }
}
