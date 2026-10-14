import Foundation

public struct PostProcessorOptions: Sendable {
    public var removeNoiseTags: Bool
    public var deduplicateRepetitions: Bool
    public var insertTimestamps: Bool
    public var paragraphSilenceThreshold: Double
    public var maxParagraphLength: Int
    
    public init(
        removeNoiseTags: Bool = true,
        deduplicateRepetitions: Bool = true,
        insertTimestamps: Bool = false,
        paragraphSilenceThreshold: Double = 1.5,
        maxParagraphLength: Int = 600
    ) {
        self.removeNoiseTags = removeNoiseTags
        self.deduplicateRepetitions = deduplicateRepetitions
        self.insertTimestamps = insertTimestamps
        self.paragraphSilenceThreshold = paragraphSilenceThreshold
        self.maxParagraphLength = maxParagraphLength
    }
}

public final class TranscriptPostProcessor: Sendable {
    public init() {}
    
    public func process(segments: [Segment], options: PostProcessorOptions = .init()) -> String {
        guard !segments.isEmpty else { return "" }
        
        var cleanedSegments: [Segment] = []
        var repetitionCount = 0
        var lastNormalizedText = ""
        
        for segment in segments {
            var text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 1. Remove noise tags like [BLANK_AUDIO], [Music], (müzik)
            if options.removeNoiseTags {
                text = cleanNoiseTags(text)
            }
            
            guard !text.isEmpty else { continue }
            
            // 2. Repetition loop detection
            let normalized = text.lowercased()
            if options.deduplicateRepetitions {
                if normalized == lastNormalizedText {
                    repetitionCount += 1
                    if repetitionCount >= 3 {
                        Log.warning("Tekrar döngüsü atlandı: '\(text)' (zaman: \(segment.start))")
                        continue
                    }
                } else {
                    lastNormalizedText = normalized
                    repetitionCount = 1
                }
            }
            
            cleanedSegments.append(Segment(start: segment.start, end: segment.end, text: text))
        }
        
        guard !cleanedSegments.isEmpty else { return "" }
        
        // 3. Paragraphing
        var paragraphs: [String] = []
        var currentParagraphWords: [String] = []
        var currentParagraphStart: Double = cleanedSegments[0].start
        var lastSegmentEnd: Double = cleanedSegments[0].start
        
        for segment in cleanedSegments {
            let silence = segment.start - lastSegmentEnd
            let currentLength = currentParagraphWords.joined(separator: " ").count
            let isSentenceEnding = segment.text.hasSuffix(".") || segment.text.hasSuffix("?") || segment.text.hasSuffix("!")
            
            let shouldBreak = !currentParagraphWords.isEmpty && (
                silence >= options.paragraphSilenceThreshold ||
                (currentLength >= options.maxParagraphLength && isSentenceEnding)
            )
            
            if shouldBreak {
                let paragraphText = finalizeParagraph(
                    words: currentParagraphWords,
                    startTime: currentParagraphStart,
                    withTimestamp: options.insertTimestamps
                )
                paragraphs.append(paragraphText)
                currentParagraphWords.removeAll()
                currentParagraphStart = segment.start
            }
            
            currentParagraphWords.append(segment.text)
            lastSegmentEnd = segment.end
        }
        
        if !currentParagraphWords.isEmpty {
            let paragraphText = finalizeParagraph(
                words: currentParagraphWords,
                startTime: currentParagraphStart,
                withTimestamp: options.insertTimestamps
            )
            paragraphs.append(paragraphText)
        }
        
        return paragraphs.joined(separator: "\n\n")
    }
    
    private func cleanNoiseTags(_ text: String) -> String {
        let pattern = #"(\[(blank_audio|music|applause|laughter|\.\.\.)\]|\((müzik|alkış|gülüş)\))"#
        let cleaned = text.replacingOccurrences(
            of: pattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func finalizeParagraph(words: [String], startTime: Double, withTimestamp: Bool) -> String {
        let text = words.joined(separator: " ")
        if withTimestamp {
            let timestamp = formatTimestamp(startTime)
            return "[\(timestamp)] \(text)"
        }
        return text
    }
    
    private func formatTimestamp(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}
