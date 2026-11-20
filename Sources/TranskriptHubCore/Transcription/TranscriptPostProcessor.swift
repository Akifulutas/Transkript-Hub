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
        paragraphSilenceThreshold: Double = 2.5,
        maxParagraphLength: Int = 650
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
    
    /// Pure hallucination phrases that are NEVER legitimate speech in normal conversations or meetings
    /// and represent known pre-training / silence artifacts in Whisper models.
    private static let pureHallucinationPhrases: Set<String> = [
        "es heilt die göttliche kraft",
        "ich hoffe es hilft es heilt die göttliche kraft",
        "göttliche kraft",
        "altyazı mk",
        "subtitles by",
        "subtitles by the amaraorg community"
    ]
    
    private static let knownHallucinationPhrases: Set<String> = [
        "thank you",
        "thank you for watching",
        "thanks for watching",
        "thank you very much",
        "thank you so much",
        "please subscribe",
        "please subscribe to the channel",
        "like and subscribe",
        "lütfen abone olun",
        "abone olmayı unutmayın",
        "izlediğiniz için teşekkürler",
        "izlediğiniz için teşekkür ederim",
        "altyazı",
        "altyazı m.k.",
        "subtitles by",
        "vielen dank fürs zuschauen",
        "danke fürs zuschauen",
        "danke fürs zusehen",
        "vielen dank für ihre aufmerksamkeit",
        "vielen dank für eure aufmerksamkeit",
        "es heilt die göttliche kraft",
        "ich hoffe, es hilft, es heilt die göttliche kraft",
        "göttliche kraft"
    ]
    
    private static func isPureHallucination(_ normalized: String) -> Bool {
        let clean = normalized.replacingOccurrences(of: ".", with: "")
                              .replacingOccurrences(of: ",", with: "")
                              .replacingOccurrences(of: "!", with: "")
        if pureHallucinationPhrases.contains(clean) { return true }
        for phrase in pureHallucinationPhrases {
            if clean.contains(phrase) {
                return true
            }
        }
        return false
    }
    
    private static func isKnownHallucination(_ normalized: String) -> Bool {
        if isPureHallucination(normalized) { return true }
        if knownHallucinationPhrases.contains(normalized) { return true }
        if normalized.count < 45 {
            for phrase in knownHallucinationPhrases {
                if normalized == phrase || normalized.hasPrefix(phrase + " ") || normalized.hasSuffix(" " + phrase) {
                    return true
                }
            }
        }
        return false
    }
    
    private func filterHallucinations(from text: String) -> String {
        let norm = normalizeForLoopDetection(text)
        if Self.isPureHallucination(norm) {
            return ""
        }
        
        let sentences = text.components(separatedBy: ". ")
        if sentences.count <= 1 {
            return text
        }
        let filtered = sentences.filter { s in
            let sNorm = normalizeForLoopDetection(s)
            return !Self.isPureHallucination(sNorm)
        }
        return filtered.joined(separator: ". ")
    }
    
    private func normalizeForLoopDetection(_ text: String) -> String {
        text.lowercased()
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
    }
    
    /// Deduplicates intra-segment repetitive loops where phrases or sentences repeat consecutively.
    public func deduplicatePhrases(_ text: String) -> String {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard words.count >= 4 else { return text }
        
        func normWord(_ w: String) -> String {
            w.lowercased().trimmingCharacters(in: .punctuationCharacters)
        }
        let normWords = words.map { normWord($0) }
        
        var resultWords: [String] = []
        var i = 0
        let total = words.count
        
        while i < total {
            var foundRepeat = false
            let maxWindow = min(20, (total - i) / 2)
            if maxWindow >= 1 {
                for window in stride(from: maxWindow, through: 1, by: -1) {
                    let currentSlice = normWords[i ..< (i + window)]
                    // If a window > 1 consists of only a single distinct repeated word (e.g. ["ja", "ja"]),
                    // skip it so the window=1 branch handles it with single-word repetition logic.
                    if window > 1 && Set(currentSlice).count <= 1 {
                        continue
                    }
                    
                    var count = 1
                    while (i + (count + 1) * window) <= total {
                        let nextSlice = normWords[(i + count * window) ..< (i + (count + 1) * window)]
                        if currentSlice.elementsEqual(nextSlice) {
                            count += 1
                        } else {
                            break
                        }
                    }
                    
                    let shouldCollapse: Bool
                    if window == 1 {
                        shouldCollapse = (count >= 4)
                    } else if window <= 3 {
                        shouldCollapse = (count >= 3)
                    } else {
                        shouldCollapse = (count >= 2)
                    }
                    
                    if shouldCollapse {
                        let keepCount = (window == 1 && count >= 4) ? 2 : 1
                        for k in 0 ..< (keepCount * window) {
                            resultWords.append(words[i + k])
                        }
                        
                        let lastRepeatedWord = words[i + count * window - 1]
                        if let lastChar = lastRepeatedWord.last, [".", "?", "!"].contains(String(lastChar)) {
                            if let lastKept = resultWords.last, let keptChar = lastKept.last, ![".", "?", "!"].contains(String(keptChar)) {
                                var cleanedKept = lastKept.trimmingCharacters(in: CharacterSet(charactersIn: ",;:-"))
                                cleanedKept.append(lastChar)
                                resultWords[resultWords.count - 1] = cleanedKept
                            }
                        }
                        
                        i += count * window
                        foundRepeat = true
                        break
                    }
                }
            }
            
            if !foundRepeat {
                resultWords.append(words[i])
                i += 1
            }
        }
        
        return resultWords.joined(separator: " ")
    }
    
    public func process(segments: [Segment], options: PostProcessorOptions = .init()) -> String {
        guard !segments.isEmpty else { return "" }
        
        var cleanedSegments: [Segment] = []
        var repetitionCount = 0
        var lastNormalizedText = ""
        var recentNormalized: [String] = []
        
        for segment in segments {
            var text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 1. Remove noise tags like [BLANK_AUDIO], [Music], (müzik)
            if options.removeNoiseTags {
                text = cleanNoiseTags(text)
            }
            
            guard !text.isEmpty else { continue }
            
            // 2. Pure Hallucination Filter: Filter out known pure silence artifacts
            text = filterHallucinations(from: text)
            guard !text.isEmpty else { continue }
            
            // 3. Intra-segment phrase-level deduplication
            if options.deduplicateRepetitions {
                text = deduplicatePhrases(text)
            }
            guard !text.isEmpty else { continue }
            
            // 4. Repetition & Hallucination loop detection across segments
            let processedNormalized = normalizeForLoopDetection(text)
            if options.deduplicateRepetitions {
                if processedNormalized == lastNormalizedText {
                    repetitionCount += 1
                    if repetitionCount >= 3 || (repetitionCount >= 2 && Self.isKnownHallucination(processedNormalized)) {
                        Log.warning("Repetition loop skipped: '\(text)' (time: \(segment.start))")
                        continue
                    }
                } else if !recentNormalized.isEmpty && recentNormalized.suffix(3).contains(processedNormalized) && Self.isKnownHallucination(processedNormalized) {
                    // Alternating hallucination loop (e.g. "Thank you" -> "Thank you for watching" -> "Thank you")
                    Log.warning("Alternating hallucination loop skipped: '\(text)' (time: \(segment.start))")
                    continue
                } else {
                    lastNormalizedText = processedNormalized
                    repetitionCount = 1
                }
                recentNormalized.append(processedNormalized)
                if recentNormalized.count > 6 {
                    recentNormalized.removeFirst()
                }
            }
            
            cleanedSegments.append(Segment(start: segment.start, end: segment.end, text: text))
        }
        
        guard !cleanedSegments.isEmpty else { return "" }
        
        // 3. Paragraphing
        var paragraphs: [String] = []
        var currentParagraphWords: [String] = []
        var currentParagraphLength: Int = 0
        var currentParagraphStart: Double = cleanedSegments[0].start
        var lastSegmentEnd: Double = cleanedSegments[0].start
        
        for segment in cleanedSegments {
            let silence = segment.start - lastSegmentEnd
            let isSentenceEnding = segment.text.hasSuffix(".") || segment.text.hasSuffix("?") || segment.text.hasSuffix("!")
            
            let shouldBreak = !currentParagraphWords.isEmpty && (
                (silence >= options.paragraphSilenceThreshold && (currentParagraphLength >= 140 || isSentenceEnding)) ||
                (currentParagraphLength >= options.maxParagraphLength && isSentenceEnding)
            )
            
            if shouldBreak {
                let paragraphText = finalizeParagraph(
                    words: currentParagraphWords,
                    startTime: currentParagraphStart,
                    withTimestamp: options.insertTimestamps
                )
                paragraphs.append(paragraphText)
                currentParagraphWords.removeAll()
                currentParagraphLength = 0
                currentParagraphStart = segment.start
            }
            
            currentParagraphLength += currentParagraphWords.isEmpty ? segment.text.count : (segment.text.count + 1)
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
        let pattern = #"((\[|\(|\*|♪)\s*(blank_audio|music|applause|laughter|müzik|alkış|gülüş|gülüşmeler|kahkaha|sessizlik|silence|neşeli müzik|\.\.\.)\s*(\]|\)|\*|♪)|♪+)"#
        var cleaned = text.replacingOccurrences(
            of: pattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }
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
