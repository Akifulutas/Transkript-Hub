import Foundation
import NaturalLanguage

public struct TranscriptSummary: Sendable, Codable, Equatable {
    public let executiveSummary: String
    public let keyPoints: [String]
    public let actionItems: [String]
    public let chapters: [TranscriptChapter]
    
    public init(
        executiveSummary: String,
        keyPoints: [String] = [],
        actionItems: [String] = [],
        chapters: [TranscriptChapter] = []
    ) {
        self.executiveSummary = executiveSummary
        self.keyPoints = keyPoints
        self.actionItems = actionItems
        self.chapters = chapters
    }
}

public struct TranscriptChapter: Sendable, Codable, Equatable, Identifiable {
    public var id: String { "\(start)_\(title)" }
    public let start: Double
    public let end: Double
    public let title: String
    public let summary: String
    
    public init(start: Double, end: Double, title: String, summary: String) {
        self.start = start
        self.end = end
        self.title = title
        self.summary = summary
    }
}

public final class TranscriptSummarizer: Sendable {
    
    public init() {}
    
    // Common stop words in Turkish and English to ignore during salience calculation
    private static let stopWords: Set<String> = [
        // Turkish
        "ve", "veya", "ile", "için", "bir", "bu", "şu", "o", "da", "de", "ta", "te", "mi", "mı", "mu", "mü",
        "ne", "var", "yok", "ama", "fakat", "lakin", "ancak", "çünkü", "gibi", "kadar", "daha", "en", "çok",
        "az", "ben", "sen", "biz", "siz", "onlar", "bunu", "şunu", "onu", "buna", "şuna", "ona", "olarak",
        // English
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by", "from",
        "is", "are", "was", "were", "be", "been", "being", "have", "has", "had", "do", "does", "did",
        "this", "that", "these", "those", "i", "you", "he", "she", "it", "we", "they", "my", "your",
        "his", "her", "our", "their", "so", "than", "too", "very", "can", "could", "would"
    ]
    
    // Action / commitment triggers (Turkish and English)
    private static let actionTriggers: [String] = [
        // Turkish modal suffixes and action words
        "malı", "meli", "malıyız", "meliyiz", "malıdır", "melidir",
        "gerekiyor", "gerekir", "şart", "zorunlu", "lazım",
        "yapılacak", "tamamlanacak", "hazırlanacak", "çözülecek", "incelenecek",
        "kararlaştırıldı", "karar verildi", "yapılmalıdır", "edilecektir", "incelenecektir",
        "görev", "aksiyon", "hedef", "teslim",
        // English modal verbs and action phrases
        "must", "should", "need to", "needs to", "have to", "has to",
        "will", "todo", "action item", "make sure", "ensure", "assign",
        "deadline", "follow up", "next step", "takeaway", "scheduled to"
    ]
    
    /// Summarizes transcript from structured segments
    public func summarize(segments: [Segment]) -> TranscriptSummary {
        guard !segments.isEmpty else {
            return TranscriptSummary(executiveSummary: "", keyPoints: [], actionItems: [], chapters: [])
        }
        
        let fullText = segments.map(\.text).joined(separator: "\n")
        let totalDuration = segments.last?.end ?? 0.0
        
        let baseSummary = summarize(text: fullText, duration: totalDuration)
        let generatedChapters = generateChapters(from: segments)
        
        return TranscriptSummary(
            executiveSummary: baseSummary.executiveSummary,
            keyPoints: baseSummary.keyPoints,
            actionItems: baseSummary.actionItems,
            chapters: generatedChapters.isEmpty ? baseSummary.chapters : generatedChapters
        )
    }
    
    /// Summarizes raw transcript text
    public func summarize(text: String, duration: Double? = nil) -> TranscriptSummary {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return TranscriptSummary(executiveSummary: "", keyPoints: [], actionItems: [], chapters: [])
        }
        
        // 1. Sentence extraction using NaturalLanguage NLTokenizer
        let sentences = extractSentences(from: trimmed)
        guard !sentences.isEmpty else {
            return TranscriptSummary(executiveSummary: trimmed, keyPoints: [trimmed], actionItems: [], chapters: [])
        }
        
        if sentences.count == 1 {
            let single = sentences[0]
            let actions = isActionSentence(single) ? [single] : []
            let ch = TranscriptChapter(start: 0.0, end: duration ?? 0.0, title: generateChapterTitle(from: single), summary: single)
            return TranscriptSummary(
                executiveSummary: single,
                keyPoints: [single],
                actionItems: actions,
                chapters: [ch]
            )
        }
        
        // 2. Frequency scoring across non-stop words
        var termFrequencies: [String: Double] = [:]
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = trimmed
        
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { tokenRange, _ in
            let word = trimmed[tokenRange].lowercased()
            if word.count >= 2 && !Self.stopWords.contains(word) {
                termFrequencies[word, default: 0.0] += 1.0
            }
            return true
        }
        
        // 3. Sentence scoring based on TF
        struct ScoredSentence {
            let index: Int
            let text: String
            let score: Double
        }
        
        var scored: [ScoredSentence] = []
        for (idx, sentence) in sentences.enumerated() {
            var sentenceScore: Double = 0.0
            var wordCount: Double = 0.0
            
            let words = sentence.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            for token in words {
                let w = token.lowercased()
                if let freq = termFrequencies[w] {
                    sentenceScore += freq
                }
                wordCount += 1.0
            }
            
            // Normalize score by square root of length to avoid purely favoring long sentences
            let normalized = wordCount > 0 ? (sentenceScore / sqrt(max(1.0, wordCount))) : 0.0
            scored.append(ScoredSentence(index: idx, text: sentence, score: normalized))
        }
        
        // Top 3 to 5 key sentences (preserving original chronological order)
        let targetCount = min(5, max(2, sentences.count / 4))
        let topScored = scored.sorted { $0.score > $1.score }.prefix(targetCount)
        let chronologicalKeySentences = topScored.sorted { $0.index < $1.index }.map(\.text)
        
        // Executive Summary: First 2-3 chronological top sentences joined
        let execCount = min(3, chronologicalKeySentences.count)
        let executiveSummary = chronologicalKeySentences.prefix(execCount).joined(separator: " ")
        
        // 4. Action Item Detection
        var actionItems: [String] = []
        for sentence in sentences {
            if isActionSentence(sentence) {
                actionItems.append(sentence)
            }
        }
        
        // 5. Generate Chapters from text if no segments
        let chapters = generateTextChapters(sentences: sentences, duration: duration ?? Double(sentences.count * 4))
        
        return TranscriptSummary(
            executiveSummary: executiveSummary.isEmpty ? trimmed : executiveSummary,
            keyPoints: chronologicalKeySentences,
            actionItems: actionItems,
            chapters: chapters
        )
    }
    
    // MARK: - Helper Methods
    
    private func extractSentences(from text: String) -> [String] {
        var results: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                results.append(sentence)
            }
            return true
        }
        
        // Fallback to newline split if tokenizer returned single block
        if results.count <= 1 && text.contains("\n") {
            let lines = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if lines.count > 1 {
                return lines
            }
        }
        
        return results
    }
    
    private func isActionSentence(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        for trigger in Self.actionTriggers {
            if lower.contains(trigger) {
                return true
            }
        }
        return false
    }
    
    private func generateChapters(from segments: [Segment]) -> [TranscriptChapter] {
        guard !segments.isEmpty else { return [] }
        
        // Group segments into chapters based on significant pauses (>= 2.5s) or time blocks (~120s - 300s)
        var chapters: [TranscriptChapter] = []
        var currentChunk: [Segment] = []
        let maxChapterDuration: Double = 180.0 // 3 minutes per chapter nominal
        
        for (_, seg) in segments.enumerated() {
            if currentChunk.isEmpty {
                currentChunk.append(seg)
                continue
            }
            
            let chunkStart = currentChunk.first!.start
            let durationSoFar = seg.end - chunkStart
            let pauseFromPrevious = seg.start - currentChunk.last!.end
            
            // Chapter boundary condition
            let isTimeSplit = durationSoFar >= maxChapterDuration
            let isSignificantPause = pauseFromPrevious >= 2.5 && currentChunk.count >= 2
            let isExplicitChapterText = seg.text.lowercased().hasPrefix("bölüm") || seg.text.lowercased().hasPrefix("chapter")
            
            if isTimeSplit || isSignificantPause || isExplicitChapterText {
                if let chapter = makeChapter(from: currentChunk, chapterIndex: chapters.count + 1) {
                    chapters.append(chapter)
                }
                currentChunk = [seg]
            } else {
                currentChunk.append(seg)
            }
        }
        
        if !currentChunk.isEmpty, let lastChapter = makeChapter(from: currentChunk, chapterIndex: chapters.count + 1) {
            chapters.append(lastChapter)
        }
        
        return chapters
    }
    
    private func makeChapter(from chunk: [Segment], chapterIndex: Int) -> TranscriptChapter? {
        guard let first = chunk.first, let last = chunk.last else { return nil }
        let combinedText = chunk.map(\.text).joined(separator: " ")
        let title = generateChapterTitle(from: combinedText, fallbackIndex: chapterIndex)
        
        // Summary: first 1 or 2 sentences
        let sentences = extractSentences(from: combinedText)
        let summary = sentences.prefix(2).joined(separator: " ")
        
        return TranscriptChapter(
            start: first.start,
            end: last.end,
            title: title,
            summary: summary.isEmpty ? combinedText : summary
        )
    }
    
    private func generateTextChapters(sentences: [String], duration: Double) -> [TranscriptChapter] {
        guard !sentences.isEmpty else { return [] }
        
        let sentencesPerChapter = max(3, sentences.count / 4)
        let chunks = stride(from: 0, to: sentences.count, by: sentencesPerChapter).map {
            Array(sentences[$0..<min($0 + sentencesPerChapter, sentences.count)])
        }
        
        let durationPerChunk = max(1.0, duration / Double(chunks.count))
        var chapters: [TranscriptChapter] = []
        
        for (idx, chunk) in chunks.enumerated() {
            let start = Double(idx) * durationPerChunk
            let end = min(duration, start + durationPerChunk)
            let combined = chunk.joined(separator: " ")
            let title = generateChapterTitle(from: combined, fallbackIndex: idx + 1)
            let summary = chunk.prefix(2).joined(separator: " ")
            
            chapters.append(TranscriptChapter(
                start: (start * 10).rounded() / 10,
                end: (end * 10).rounded() / 10,
                title: title,
                summary: summary
            ))
        }
        
        return chapters
    }
    
    private func generateChapterTitle(from text: String, fallbackIndex: Int = 1) -> String {
        // Look for explicit markers like "Bölüm: X", "Chapter: X"
        let lower = text.lowercased()
        if let range = lower.range(of: "bölüm") ?? lower.range(of: "chapter") {
            let substring = text[range.lowerBound...]
            let line = substring.components(separatedBy: CharacterSet(charactersIn: ".:\n")).first ?? ""
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 4 && trimmed.count <= 50 {
                return trimmed
            }
        }
        
        // Extract dominant noun phrase or key words
        var salientWords: [String] = []
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range])
            if word.count >= 4 && !Self.stopWords.contains(word.lowercased()) {
                if !salientWords.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
                    salientWords.append(word.capitalized)
                }
            }
            return salientWords.count < 3
        }
        
        if salientWords.count >= 2 {
            return salientWords.joined(separator: " & ")
        } else if let first = salientWords.first {
            return "\(first) Değerlendirmesi"
        }
        
        return "Bölüm \(fallbackIndex)"
    }
}
