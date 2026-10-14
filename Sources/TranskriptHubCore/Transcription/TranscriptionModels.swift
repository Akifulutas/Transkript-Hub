import Foundation

public struct Segment: Sendable, Codable, Equatable {
    public let start: Double // seconds
    public let end: Double   // seconds
    public let text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
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
    
    public init(
        language: String? = nil,
        useVAD: Bool = true,
        threads: Int = ProcessInfo.processInfo.activeProcessorCount,
        initialPrompt: String? = nil
    ) {
        self.language = language
        self.useVAD = useVAD
        self.threads = max(1, threads)
        self.initialPrompt = initialPrompt
    }
}
