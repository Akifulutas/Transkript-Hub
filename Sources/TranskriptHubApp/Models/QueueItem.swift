import Foundation
import TranskriptHubCore

public enum QueueItemKind: Hashable, Sendable {
    case youtube(ParsedYouTubeVideo)
    case audioFile(URL)
}

public enum QueueItemState: String, Hashable, Sendable {
    case queued = "Kuyrukta"
    case fetching = "İndiriliyor"
    case transcribing = "Transkript Ediliyor"
    case completed = "Tamamlandı"
    case failed = "Hata"
}

public struct QueueItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: QueueItemKind
    public var title: String
    public var subtitle: String
    public var durationSec: Double?
    public var state: QueueItemState
    public var progress: Double // 0.0 ... 1.0
    public var transcript: String?
    public var outputURL: URL?
    public var errorMessage: String?
    public let addedAt: Date
    
    public init(
        id: String = UUID().uuidString,
        kind: QueueItemKind,
        title: String,
        subtitle: String,
        durationSec: Double? = nil,
        state: QueueItemState = .queued,
        progress: Double = 0.0,
        transcript: String? = nil,
        outputURL: URL? = nil,
        errorMessage: String? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.durationSec = durationSec
        self.state = state
        self.progress = progress
        self.transcript = transcript
        self.outputURL = outputURL
        self.errorMessage = errorMessage
        self.addedAt = addedAt
    }
    
    public var isYouTube: Bool {
        if case .youtube = kind { return true }
        return false
    }
    
    public var canonicalURL: String? {
        if case .youtube(let video) = kind {
            return video.canonicalURL
        }
        return nil
    }
}

public struct HistoryItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let kind: String // "youtube" | "audio"
    public let outputPath: String
    public let date: Date
    public let snippet: String
    
    public init(id: String = UUID().uuidString, title: String, kind: String, outputPath: String, date: Date, snippet: String) {
        self.id = id
        self.title = title
        self.kind = kind
        self.outputPath = outputPath
        self.date = date
        self.snippet = snippet
    }
}
