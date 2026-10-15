import Foundation

public struct Word: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: String { "\(start)_\(end)_\(text)" }
    public let text: String
    public let start: Double // seconds
    public let end: Double   // seconds
    public let confidence: Float
    
    public init(text: String, start: Double, end: Double, confidence: Float = 1.0) {
        self.text = text
        self.start = start
        self.end = end
        self.confidence = confidence
    }
    
    public var duration: Double {
        max(0, end - start)
    }
    
    public func contains(time: Double) -> Bool {
        time >= start && time <= end
    }
}

public struct Segment: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: String { "\(start)_\(end)_\(text)" }
    public var start: Double // seconds
    public var end: Double   // seconds
    public var text: String
    public var speaker: String?
    public var words: [Word]

    public init(
        start: Double,
        end: Double,
        text: String,
        speaker: String? = nil,
        words: [Word] = []
    ) {
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
        self.words = words
    }
    
    enum CodingKeys: String, CodingKey {
        case start
        case end
        case text
        case speaker
        case words
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.start = try container.decode(Double.self, forKey: .start)
        self.end = try container.decode(Double.self, forKey: .end)
        self.text = try container.decode(String.self, forKey: .text)
        self.speaker = try container.decodeIfPresent(String.self, forKey: .speaker)
        self.words = try container.decodeIfPresent([Word].self, forKey: .words) ?? []
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(speaker, forKey: .speaker)
        try container.encode(words, forKey: .words)
    }
    
    public var duration: Double {
        max(0, end - start)
    }
    
    public func contains(time: Double) -> Bool {
        time >= start && time <= end
    }
    
    public func word(at time: Double) -> Word? {
        words.first { $0.contains(time: time) }
    }
    
    public static func interpolateWords(for text: String, start: Double, end: Double) -> [Word] {
        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return [] }
        
        let totalDuration = max(0.05, end - start)
        let step = totalDuration / Double(tokens.count)
        
        return tokens.enumerated().map { index, token in
            let wordStart = start + (Double(index) * step)
            let wordEnd = min(end, wordStart + step)
            return Word(
                text: token,
                start: (wordStart * 1000).rounded() / 1000,
                end: (wordEnd * 1000).rounded() / 1000,
                confidence: 1.0
            )
        }
    }
}

public struct TranscriptResult: Sendable, Codable, Equatable {
    public let segments: [Segment]
    public let detectedLanguage: String?

    public init(segments: [Segment], detectedLanguage: String?) {
        self.segments = segments
        self.detectedLanguage = detectedLanguage
    }
    
    public var fullText: String {
        segments.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct TranscriptionOptions: Sendable {
    public var language: String?        // nil = auto
    public var useVAD: Bool             // default true
    public var threads: Int             // default: performance core count
    public var initialPrompt: String?   // optional terms list
    public var tokenTimestamps: Bool    // default: true
    
    public init(
        language: String? = nil,
        useVAD: Bool = true,
        threads: Int = min(ProcessInfo.processInfo.activeProcessorCount, 6),
        initialPrompt: String? = nil,
        tokenTimestamps: Bool = true
    ) {
        self.language = language
        self.useVAD = useVAD
        self.threads = max(1, threads)
        self.initialPrompt = initialPrompt
        self.tokenTimestamps = tokenTimestamps
    }
}
