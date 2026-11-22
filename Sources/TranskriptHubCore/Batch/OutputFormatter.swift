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
    public static let richVideoInfoHeader = "VİDEO BİLGİLERİ"
    public static let richDescriptionHeader = "📝 VİDEO AÇIKLAMASI"
    private static let sectionDivider = "----------------------------------------"
    private static let richBanner = "================================================================================"
    
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
    /// without duplicating the description block if it is already present (supports both legacy and rich documents).
    public static func ensureYouTubeDescriptionIncluded(
        transcript: String,
        description: String?
    ) -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTranscript.hasPrefix(youtubeDescriptionHeader) ||
            trimmedTranscript.contains(richDescriptionHeader) ||
            trimmedTranscript.contains(richVideoInfoHeader) {
            return trimmedTranscript
        }
        return formatYouTubeTranscript(transcript: trimmedTranscript, description: description)
    }
    
    /// Extracts the video description block back from a formatted YouTube transcript (both legacy and rich formats).
    public static func extractYouTubeDescription(from formattedTranscript: String) -> String? {
        let trimmed = formattedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(youtubeDescriptionHeader) {
            let afterHeader = trimmed.dropFirst(youtubeDescriptionHeader.count)
            guard let dividerRange = afterHeader.range(of: "\n\n\(sectionDivider)\n\n\(youtubeTranscriptHeader)") else {
                return nil
            }
            let desc = afterHeader[..<dividerRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            return desc.isEmpty ? nil : desc
        }
        let richMarker = "\(richBanner)\n\(richDescriptionHeader)\n\(richBanner)\n"
        if let startRange = trimmed.range(of: richMarker) {
            let remainder = trimmed[startRange.upperBound...]
            if let nextBanner = remainder.range(of: "\n\n\(richBanner)") {
                let desc = remainder[..<nextBanner.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                return desc.isEmpty ? nil : desc
            } else {
                let desc = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
                return desc.isEmpty ? nil : desc
            }
        }
        return nil
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
    
    // MARK: - Maximum-Data Zero-Cost YouTube Document Formatter
    
    /// Formats compact human-readable counts (e.g. `6_740_000` -> `6.74M`, `48_200` -> `48.2K`).
    public static func formatCompactCount(_ value: Int) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.2fB", Double(value) / 1_000_000_000.0)
        } else if value >= 1_000_000 {
            return String(format: "%.2fM", Double(value) / 1_000_000.0)
        } else if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000.0)
        }
        return "\(value)"
    }
    
    /// Formats `yt-dlp` `YYYYMMDD` upload date strings as `YYYY-MM-DD`.
    public static func formatUploadDate(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.count == 8,
              raw.allSatisfy(\.isNumber) else {
            return nil
        }
        let y = raw.prefix(4)
        let m = raw.dropFirst(4).prefix(2)
        let d = raw.suffix(2)
        return "\(y)-\(m)-\(d)"
    }
    
    /// Extracts the top 3–5 "Most Replayed" viewer intensity peaks from YouTube's 100-bucket heatmap.
    public static func extractHeatmapPeaks(
        from heatmap: [YouTubeHeatmapPoint]?,
        minIntensity: Double = 0.65,
        mergeGapSeconds: Double = 15.0,
        maxPeaks: Int = 5
    ) -> [YouTubeHeatmapPoint] {
        guard let heatmap = heatmap, !heatmap.isEmpty else { return [] }
        let highPoints = heatmap
            .filter { $0.value >= minIntensity && $0.endTime >= $0.startTime }
            .sorted { $0.startTime < $1.startTime }
        guard !highPoints.isEmpty else { return [] }
        
        var merged: [YouTubeHeatmapPoint] = []
        for pt in highPoints {
            if let last = merged.last, pt.startTime <= last.endTime + mergeGapSeconds {
                let updated = YouTubeHeatmapPoint(
                    startTime: last.startTime,
                    endTime: max(last.endTime, pt.endTime),
                    value: max(last.value, pt.value)
                )
                merged[merged.count - 1] = updated
            } else {
                merged.append(pt)
            }
        }
        
        let top = merged
            .sorted { $0.value > $1.value }
            .prefix(maxPeaks)
            .sorted { $0.startTime < $1.startTime }
        return Array(top)
    }
    
    /// Extracts a concise spoken transcript excerpt overlapping `[start, end]`.
    public static func excerptForRange(
        start: Double,
        end: Double,
        segments: [Segment],
        maxLength: Int = 220
    ) -> String? {
        let lower = max(0, start - 2.0)
        let upper = max(end, start) + 2.0
        let overlapping = segments.filter { seg in
            seg.end >= lower && seg.start <= upper && !seg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !overlapping.isEmpty else { return nil }
        let joined = overlapping
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if joined.count <= maxLength {
            return joined
        }
        let idx = joined.index(joined.startIndex, offsetBy: maxLength)
        return String(joined[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
    
    /// Extracts unique HTTP/HTTPS URLs from video description and comments while preserving discovery order.
    public static func extractUniqueURLs(
        from texts: [String?],
        excluding excludedURLs: Set<String> = []
    ) -> [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        var seen: Set<String> = excludedURLs
        var results: [String] = []
        
        for optionalText in texts {
            guard let text = optionalText, !text.isEmpty else { continue }
            let nsText = text as NSString
            let matches = detector.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                guard let url = match.url,
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" else { continue }
                let cleaned = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: ".,);]\"'"))
                if !cleaned.isEmpty && !seen.contains(cleaned) {
                    seen.insert(cleaned)
                    results.append(cleaned)
                }
            }
        }
        return results
    }
    
    /// Curates YouTube comments with Pinned first, then Channel Owner (`isUploader`), then top liked comments.
    public static func curateComments(
        _ comments: [YouTubeComment]?,
        maxCount: Int = 15
    ) -> [YouTubeComment] {
        guard let comments = comments, !comments.isEmpty else { return [] }
        let nonEmpty = comments.filter {
            guard let t = $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
            return !t.isEmpty
        }
        
        let sorted = nonEmpty.sorted { lhs, rhs in
            let lPin = lhs.isPinned == true ? 2 : (lhs.isUploader == true ? 1 : 0)
            let rPin = rhs.isPinned == true ? 2 : (rhs.isUploader == true ? 1 : 0)
            if lPin != rPin { return lPin > rPin }
            return (lhs.likeCount ?? 0) > (rhs.likeCount ?? 0)
        }
        
        var seen: Set<String> = []
        var curated: [YouTubeComment] = []
        for c in sorted {
            let key = "\(c.author ?? "")|\(c.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            curated.append(c)
            if curated.count >= maxCount { break }
        }
        return curated
    }
    
    /// Builds a single maximum-data, zero-API-cost `.txt` document for a YouTube video containing:
    /// Video Identity & Stats, Chapters TOC, Most Replayed Heatmap Peaks, SponsorBlock Tags & Highlight,
    /// Extracted Resource URL Index, Full Description, Pinned/Uploader/Top Comments,
    /// and Timestamped + Chapter-Headed Transcript with inline `[SPONSOR]` markers.
    public static func formatRichYouTubeDocument(
        metadata: YouTubeMetadata,
        segments: [Segment],
        canonicalURL: String? = nil,
        sponsorSegments: [SponsorBlockSegment] = [],
        postProcessor: TranscriptPostProcessor = TranscriptPostProcessor(),
        options: PostProcessorOptions = PostProcessorOptions()
    ) -> String {
        var blocks: [String] = []
        let resolvedURL = canonicalURL ?? "https://www.youtube.com/watch?v=\(metadata.id)"
        let resolvedChapters = resolveChapters(nativeChapters: metadata.chapters, description: metadata.description)
        let curatedComments = curateComments(metadata.comments)
        
        // 1. VİDEO BİLGİLERİ
        var infoLines: [String] = []
        infoLines.append("Başlık: \(metadata.title)")
        if let channel = metadata.channel, !channel.isEmpty {
            var chLine = "Kanal: \(channel)"
            if let subs = metadata.channelFollowerCount, subs > 0 {
                chLine += " (\(formatCompactCount(subs)) abone)"
            }
            if let chURL = metadata.channelURL, !chURL.isEmpty {
                chLine += " — \(chURL)"
            }
            infoLines.append(chLine)
        }
        infoLines.append("URL: \(resolvedURL)")
        if let dateStr = formatUploadDate(metadata.uploadDate) {
            infoLines.append("Yayın Tarihi: \(dateStr)")
        }
        var metaRow: [String] = []
        if let dur = metadata.duration, dur > 0 {
            metaRow.append("Süre: \(formatChapterTimestamp(dur))")
        }
        if let live = metadata.liveStatus, !live.isEmpty {
            let liveLabel: String
            switch live {
            case "was_live": liveLabel = "Canlı Yayın Tekrarı"
            case "is_live": liveLabel = "Canlı Yayın"
            case "is_upcoming": liveLabel = "Yaklaşan Yayın"
            default: liveLabel = "Normal Video"
            }
            metaRow.append("Tür: \(liveLabel)")
        }
        if !metaRow.isEmpty {
            infoLines.append(metaRow.joined(separator: " | "))
        }
        var stats: [String] = []
        if let views = metadata.viewCount, views > 0 {
            stats.append("\(formatCompactCount(views)) izlenme")
        }
        if let likes = metadata.likeCount, likes > 0 {
            stats.append("\(formatCompactCount(likes)) beğeni")
        }
        if let cmts = metadata.commentCount, cmts > 0 {
            stats.append("\(formatCompactCount(cmts)) yorum")
        }
        if !stats.isEmpty {
            infoLines.append("İstatistikler: \(stats.joined(separator: " • "))")
        }
        if let categories = metadata.categories?.filter({ !$0.isEmpty }), !categories.isEmpty {
            infoLines.append("Kategori: \(categories.joined(separator: ", "))")
        }
        if let tags = metadata.tags?.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }), !tags.isEmpty {
            infoLines.append("Etiketler: \(tags.joined(separator: ", "))")
        }
        blocks.append("\(richBanner)\n\(richVideoInfoHeader)\n\(richBanner)\n\(infoLines.joined(separator: "\n"))")
        
        // 2. İÇİNDEKİLER (BÖLÜMLER)
        if !resolvedChapters.isEmpty {
            let tocLines = resolvedChapters.map { ch in
                "- \(formatChapterTimestamp(ch.startTime)) \(ch.title)"
            }
            blocks.append("\(richBanner)\nİÇİNDEKİLER (BÖLÜMLER)\n\(richBanner)\n\(tocLines.joined(separator: "\n"))")
        }
        
        // 3. 🔥 EN ÇOK TEKRAR İZLENEN ANLAR (HEATMAP)
        let peaks = extractHeatmapPeaks(from: metadata.heatmap)
        if !peaks.isEmpty {
            let peakLines = peaks.map { peak -> String in
                let startStr = formatChapterTimestamp(peak.startTime)
                let endStr = formatChapterTimestamp(peak.endTime)
                let pct = min(100, max(1, Int((peak.value * 100.0).rounded())))
                if let excerpt = excerptForRange(start: peak.startTime, end: peak.endTime, segments: segments) {
                    return "- [\(startStr) - \(endStr)] (Yoğunluk: %\(pct)): \"\(excerpt)\""
                } else {
                    return "- [\(startStr) - \(endStr)] (Yoğunluk: %\(pct))"
                }
            }
            blocks.append("\(richBanner)\n🔥 EN ÇOK TEKRAR İZLENEN ANLAR (HEATMAP)\n\(richBanner)\n\(peakLines.joined(separator: "\n"))")
        }
        
        // 4. 🏷️ SPONSOR / REKLAM & KİLİT ANLAR (SPONSORBLOCK)
        if !sponsorSegments.isEmpty {
            let sbLines = sponsorSegments.map { seg -> String in
                let startStr = formatChapterTimestamp(seg.startTime)
                if seg.isHighlight {
                    if let excerpt = excerptForRange(start: seg.startTime, end: seg.startTime + 10.0, segments: segments) {
                        return "- ⭐ Kilit An (Highlight): [\(startStr)] — \"\(excerpt)\""
                    }
                    return "- ⭐ Kilit An (Highlight): [\(startStr)]"
                } else {
                    let endStr = formatChapterTimestamp(seg.endTime)
                    return "- [\(seg.localizedLabel): \(startStr) - \(endStr)]"
                }
            }
            blocks.append("\(richBanner)\n🏷️ SPONSOR / REKLAM & KİLİT ANLAR (SPONSORBLOCK)\n\(richBanner)\n\(sbLines.joined(separator: "\n"))")
        }
        
        // 5. 🔗 KAYNAKLAR & LİNKLER (URL DİZİNİ)
        var linkSources: [String?] = [metadata.description]
        linkSources.append(contentsOf: curatedComments.map(\.text))
        var excluded: Set<String> = [resolvedURL]
        if let chURL = metadata.channelURL { excluded.insert(chURL) }
        let extractedLinks = extractUniqueURLs(from: linkSources, excluding: excluded)
        if !extractedLinks.isEmpty {
            let linkLines = extractedLinks.enumerated().map { idx, url in
                "\(idx + 1). \(url)"
            }
            blocks.append("\(richBanner)\n🔗 KAYNAKLAR & LİNKLER (URL DİZİNİ)\n\(richBanner)\n\(linkLines.joined(separator: "\n"))")
        }
        
        // 6. 📝 VİDEO AÇIKLAMASI
        if let desc = metadata.description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
            blocks.append("\(richBanner)\n\(richDescriptionHeader)\n\(richBanner)\n\(desc)")
        }
        
        // 7. 📌 SABİTLENMİŞ & EN ÇOK BEĞENİLEN YORUMLAR
        if !curatedComments.isEmpty {
            var commentBlocks: [String] = []
            var communityIdx = 0
            for comment in curatedComments {
                guard let rawText = comment.text?.trimmingCharacters(in: .whitespacesAndNewlines), !rawText.isEmpty else { continue }
                let author = comment.author?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Anonim"
                let likesSuffix: String
                if let likes = comment.likeCount, likes > 0 {
                    likesSuffix = " (\(formatCompactCount(likes)) beğeni)"
                } else {
                    likesSuffix = ""
                }
                let prefix: String
                if comment.isPinned == true {
                    prefix = "[📌 SABİTLENMİŞ] \(author)\(likesSuffix):"
                } else if comment.isUploader == true {
                    prefix = "[👤 KANAL SAHİBİ] \(author)\(likesSuffix):"
                } else {
                    communityIdx += 1
                    prefix = "\(communityIdx). \(author)\(likesSuffix):"
                }
                commentBlocks.append("\(prefix)\n\(rawText)")
            }
            if !commentBlocks.isEmpty {
                blocks.append("\(richBanner)\n📌 SABİTLENMİŞ & EN ÇOK BEĞENİLEN YORUMLAR\n\(richBanner)\n\(commentBlocks.joined(separator: "\n\n"))")
            }
        }
        
        // 8. 🗣️ ZAMAN DAMGALI & BÖLÜMLENDİRİLMİŞ TAM TRANSKRİPT
        let sponsorRanges = sponsorSegments.filter { $0.isSponsor || $0.category == "selfpromo" }
        let annotatedSegments: [Segment] = segments.map { seg in
            guard !sponsorRanges.isEmpty else { return seg }
            let mid = (seg.start + seg.end) * 0.5
            if let match = sponsorRanges.first(where: { mid >= $0.startTime && mid <= $0.endTime }) {
                let tag = "[\(match.localizedLabel)] "
                if !seg.text.hasPrefix(tag) {
                    return Segment(
                        start: seg.start,
                        end: seg.end,
                        text: tag + seg.text,
                        speaker: seg.speaker,
                        words: seg.words,
                        noSpeechProb: seg.noSpeechProb
                    )
                }
            }
            return seg
        }
        
        var timestampedOptions = options
        timestampedOptions.insertTimestamps = true
        let transcriptBody = resolvedChapters.isEmpty
            ? postProcessor.process(segments: annotatedSegments, options: timestampedOptions)
            : formatChapteredTranscript(
                segments: annotatedSegments,
                chapters: resolvedChapters,
                postProcessor: postProcessor,
                options: timestampedOptions
            )
        let transcriptHeader = resolvedChapters.isEmpty
            ? "🗣️ TRANSKRİPT (ZAMAN DAMGALI)"
            : "🗣️ TRANSKRİPT (ZAMAN DAMGALI & BÖLÜMLENDİRİLMİŞ)"
        blocks.append("\(richBanner)\n\(transcriptHeader)\n\(richBanner)\n\(transcriptBody)")
        
        return blocks.joined(separator: "\n\n")
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
