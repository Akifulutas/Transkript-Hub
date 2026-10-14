import Foundation

public struct BatchItemSection: Sendable {
    public let sequence: Int
    public let totalCount: Int
    public let title: String?
    public let channel: String?
    public let durationSec: Double?
    public let url: String?
    public let localFilePath: String?
    public let language: String?
    public let transcriptText: String?
    public let errorMessage: String? // If failed
    public let isYouTube: Bool
    
    public init(
        sequence: Int,
        totalCount: Int,
        title: String?,
        channel: String?,
        durationSec: Double?,
        url: String?,
        localFilePath: String? = nil,
        language: String?,
        transcriptText: String?,
        errorMessage: String?,
        isYouTube: Bool = true
    ) {
        self.sequence = sequence
        self.totalCount = totalCount
        self.title = title
        self.channel = channel
        self.durationSec = durationSec
        self.url = url
        self.localFilePath = localFilePath
        self.language = language
        self.transcriptText = transcriptText
        self.errorMessage = errorMessage
        self.isYouTube = isYouTube
    }
}

public struct BatchExportMetadata: Sendable {
    public let batchID: String
    public let sourceType: String
    public let createdAt: Date
    public let totalCount: Int
    public let completedCount: Int
    public let failedCount: Int
    public let modelName: String
    public let language: String
    
    public init(
        batchID: String,
        sourceType: String = "YouTube",
        createdAt: Date = Date(),
        totalCount: Int,
        completedCount: Int,
        failedCount: Int,
        modelName: String = "tiny",
        language: String = "auto"
    ) {
        self.batchID = batchID
        self.sourceType = sourceType
        self.createdAt = createdAt
        self.totalCount = totalCount
        self.completedCount = completedCount
        self.failedCount = failedCount
        self.modelName = modelName
        self.language = language
    }
}

public enum OutputFormatter {
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.timeZone = TimeZone.current
        return df
    }()
    
    public static func formatBatch(metadata: BatchExportMetadata, items: [BatchItemSection]) -> String {
        var lines: [String] = []
        
        // Header
        lines.append("TRANSKRIPT HUB EXPORT")
        lines.append("Format-Version: 1")
        lines.append("Batch-ID: \(metadata.batchID)")
        lines.append("Source-Type: \(metadata.sourceType)")
        lines.append("Created: \(dateFormatter.string(from: metadata.createdAt))")
        lines.append("Item-Count: \(metadata.totalCount)")
        lines.append("Completed: \(metadata.completedCount)")
        lines.append("Failed: \(metadata.failedCount)")
        lines.append("Model: \(metadata.modelName), Language: \(metadata.language)")
        lines.append("")
        
        let sortedItems = items.sorted(by: { $0.sequence < $1.sequence })
        
        for item in sortedItems {
            lines.append("====================================================================")
            let itemLabel = item.isYouTube ? "VIDEO \(item.sequence) / \(item.totalCount)" : "ITEM \(item.sequence) / \(item.totalCount)"
            lines.append(itemLabel)
            lines.append("====================================================================")
            
            lines.append("TITLE: \(item.title ?? "Bilinmiyor")")
            if let ch = item.channel, !ch.isEmpty {
                lines.append("CHANNEL: \(ch)")
            }
            if let dur = item.durationSec {
                lines.append("DURATION: \(formatDuration(dur))")
            }
            if let url = item.url {
                lines.append("URL: \(url)")
            }
            if let file = item.localFilePath {
                lines.append("FILE: \(file)")
            }
            
            if let error = item.errorMessage {
                lines.append("STATUS: İŞLENEMEDİ — \(error)")
            } else {
                if let lang = item.language {
                    lines.append("LANGUAGE: \(lang)")
                }
                lines.append("")
                lines.append("TRANSCRIPT")
                lines.append("")
                lines.append(item.transcriptText ?? "")
            }
            lines.append("")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
