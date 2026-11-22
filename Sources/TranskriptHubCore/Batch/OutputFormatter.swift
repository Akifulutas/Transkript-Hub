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
    public let videoDescription: String?
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
        videoDescription: String? = nil,
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
        self.videoDescription = videoDescription
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
    public static let youtubeDescriptionHeader = "VİDEO AÇIKLAMASI:"
    public static let youtubeTranscriptHeader = "TRANSKRİPT:"
    private static let sectionDivider = "----------------------------------------"
    
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.timeZone = TimeZone.current
        return df
    }()
    
    /// Formats a YouTube transcript with its video description section prepended cleanly when available.
    public static func formatYouTubeTranscript(
        transcript: String,
        description: String?
    ) -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawDesc = description?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawDesc.isEmpty else {
            return trimmedTranscript
        }
        return """
        \(youtubeDescriptionHeader)
        \(rawDesc)

        \(sectionDivider)

        \(youtubeTranscriptHeader)
        \(trimmedTranscript)
        """
    }
    
    /// Idempotent helper that ensures a YouTube transcript includes its video description
    /// without duplicating the description block if it is already present.
    public static func ensureYouTubeDescriptionIncluded(
        transcript: String,
        description: String?
    ) -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTranscript.hasPrefix(youtubeDescriptionHeader) {
            return trimmedTranscript
        }
        return formatYouTubeTranscript(transcript: trimmedTranscript, description: description)
    }
    
    /// Extracts the video description block back from a formatted YouTube transcript (e.g. when loaded from cache).
    public static func extractYouTubeDescription(from formattedTranscript: String) -> String? {
        let trimmed = formattedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(youtubeDescriptionHeader) else { return nil }
        let afterHeader = trimmed.dropFirst(youtubeDescriptionHeader.count)
        guard let dividerRange = afterHeader.range(of: "\n\n\(sectionDivider)\n\n\(youtubeTranscriptHeader)") else {
            return nil
        }
        let desc = afterHeader[..<dividerRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return desc.isEmpty ? nil : desc
    }
    
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
                if let desc = item.videoDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                    lines.append("")
                    lines.append("DESCRIPTION")
                    lines.append("")
                    lines.append(desc)
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
