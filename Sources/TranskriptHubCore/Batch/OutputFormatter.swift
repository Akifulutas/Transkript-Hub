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
    
    /// Formats a chapter start timestamp cleanly as `MM:SS` or `H:MM:SS`.
    public static func formatChapterTimestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
    
    /// Fallback chapter extractor that parses timestamp lines (e.g. `00:00 Intro`, `1:05:20 - Architecture`)
    /// from a YouTube video description when native `yt-dlp` chapters are absent.
    public static func parseChaptersFromDescription(_ description: String?) -> [YouTubeChapter] {
        guard let description = description, !description.isEmpty else { return [] }
        let pattern = #"^\s*[\(\[]?(\d{1,2}:\d{2}(?::\d{2})?)[\)\]]?\s*[-–—:|•]?\s*(.+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        
        var parsed: [YouTubeChapter] = []
        for rawLine in description.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            guard let match = regex.firstMatch(in: line, range: range),
                  match.numberOfRanges >= 3 else { continue }
            
            let tsStr = nsLine.substring(with: match.range(at: 1))
            let rawTitle = nsLine.substring(with: match.range(at: 2))
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—:|•")))
            guard !rawTitle.isEmpty,
                  let seconds = parseTimestampToSeconds(tsStr) else { continue }
            
            if let last = parsed.last, seconds <= last.startTime {
                continue
            }
            parsed.append(YouTubeChapter(startTime: seconds, endTime: nil, title: rawTitle))
        }
        return parsed.count >= 2 ? parsed : []
    }
    
    private static func parseTimestampToSeconds(_ ts: String) -> Double? {
        let parts = ts.split(separator: ":").compactMap { Int($0) }
        if parts.count == 2 {
            let (m, s) = (parts[0], parts[1])
            guard s >= 0 && s < 60 && m >= 0 else { return nil }
            return Double(m * 60 + s)
        } else if parts.count == 3 {
            let (h, m, s) = (parts[0], parts[1], parts[2])
            guard h >= 0 && m >= 0 && m < 60 && s >= 0 && s < 60 else { return nil }
            return Double(h * 3600 + m * 60 + s)
        }
        return nil
    }
    
    /// Resolves clean, deduplicated, ascending YouTube chapters from native `yt-dlp` metadata
    /// or falls back to parsing chapter timestamps from the video description.
    public static func resolveChapters(
        nativeChapters: [YouTubeChapter]?,
        description: String?
    ) -> [YouTubeChapter] {
        let rawList: [YouTubeChapter]
        if let native = nativeChapters, !native.isEmpty {
            rawList = native
        } else {
            rawList = parseChaptersFromDescription(description)
        }
        
        var cleaned: [YouTubeChapter] = []
        let sorted = rawList.sorted { $0.startTime < $1.startTime }
        for ch in sorted {
            let title = ch.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, ch.startTime.isFinite, ch.startTime >= 0 else { continue }
            if let last = cleaned.last, abs(last.startTime - ch.startTime) < 0.5 && last.title == title {
                continue
            }
            cleaned.append(YouTubeChapter(startTime: ch.startTime, endTime: ch.endTime, title: title))
        }
        return cleaned
    }
    
    /// Formats transcription segments into clean chapter-headed Markdown (`## 00:00 Intro`, `## 12:40 Architecture`)
    /// while preserving all `TranscriptPostProcessor` rules within each chapter and never dropping any segment.
    public static func formatChapteredTranscript(
        segments: [Segment],
        chapters: [YouTubeChapter],
        postProcessor: TranscriptPostProcessor = TranscriptPostProcessor(),
        options: PostProcessorOptions = PostProcessorOptions()
    ) -> String {
        let resolvedChapters = resolveChapters(nativeChapters: chapters, description: nil)
        guard !resolvedChapters.isEmpty, !segments.isEmpty else {
            return postProcessor.process(segments: segments, options: options)
        }
        
        var prefaceSegments: [Segment] = []
        var chapterBuckets: [[Segment]] = Array(repeating: [], count: resolvedChapters.count)
        
        for seg in segments {
            if seg.start < resolvedChapters[0].startTime {
                prefaceSegments.append(seg)
                continue
            }
            var targetIdx = resolvedChapters.count - 1
            for i in 0..<(resolvedChapters.count - 1) {
                if seg.start >= resolvedChapters[i].startTime && seg.start < resolvedChapters[i + 1].startTime {
                    targetIdx = i
                    break
                }
            }
            chapterBuckets[targetIdx].append(seg)
        }
        
        var sections: [String] = []
        if !prefaceSegments.isEmpty {
            let text = postProcessor.process(segments: prefaceSegments, options: options)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                sections.append(text)
            }
        }
        
        for (idx, chapter) in resolvedChapters.enumerated() {
            let bucket = chapterBuckets[idx]
            guard !bucket.isEmpty else { continue }
            let text = postProcessor.process(segments: bucket, options: options)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let heading = "## \(formatChapterTimestamp(chapter.startTime)) \(chapter.title)"
            sections.append("\(heading)\n\n\(text)")
        }
        
        if sections.isEmpty {
            return postProcessor.process(segments: segments, options: options)
        }
        return sections.joined(separator: "\n\n")
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
