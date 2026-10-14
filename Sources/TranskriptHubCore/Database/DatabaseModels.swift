import Foundation
import GRDB

public enum BatchKind: String, Codable, Sendable {
    case youtube
    case files
    case mixed
}

public enum BatchState: String, Codable, Sendable {
    case active
    case assembling
    case completed
    case completedWithErrors
    case cancelled
}

public struct BatchRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "batch"
    
    public var id: String
    public var createdAt: String
    public var kind: String
    public var expectedCount: Int
    public var state: String
    public var language: String?
    public var outputPath: String?
    public var cleanedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case kind
        case expectedCount = "expected_count"
        case state
        case language
        case outputPath = "output_path"
        case cleanedAt = "cleaned_at"
    }
    
    public init(
        id: String = UUID().uuidString,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        kind: BatchKind = .youtube,
        expectedCount: Int,
        state: BatchState = .active,
        language: String? = nil,
        outputPath: String? = nil,
        cleanedAt: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind.rawValue
        self.expectedCount = expectedCount
        self.state = state.rawValue
        self.language = language
        self.outputPath = outputPath
        self.cleanedAt = cleanedAt
    }
}

public enum JobState: String, Codable, Sendable {
    case queued
    case fetching
    case fetched
    case transcribing
    case transcribed
    case completed
    case retryWaiting
    case failed
    case cancelled
    
    public var isTerminal: Bool {
        self == .completed || self == .failed || self == .cancelled
    }
}

public struct JobRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "job"
    
    public var id: String
    public var batchID: String
    public var sequence: Int
    public var sourceType: String
    public var sourceURL: String?
    public var sourcePath: String?
    public var externalID: String?
    public var title: String?
    public var creator: String?
    public var durationSec: Double?
    public var state: String
    public var attempt: Int
    public var nextAttemptAt: String?
    public var errorKind: String?
    public var errorMessage: String?
    public var workspacePath: String?
    public var detectedLang: String?
    public var updatedAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case batchID = "batch_id"
        case sequence
        case sourceType = "source_type"
        case sourceURL = "source_url"
        case sourcePath = "source_path"
        case externalID = "external_id"
        case title
        case creator
        case durationSec = "duration_sec"
        case state
        case attempt
        case nextAttemptAt = "next_attempt_at"
        case errorKind = "error_kind"
        case errorMessage = "error_message"
        case workspacePath = "workspace_path"
        case detectedLang = "detected_lang"
        case updatedAt = "updated_at"
    }
    
    public init(
        id: String = UUID().uuidString,
        batchID: String,
        sequence: Int,
        sourceType: String = "youtube",
        sourceURL: String? = nil,
        sourcePath: String? = nil,
        externalID: String? = nil,
        title: String? = nil,
        creator: String? = nil,
        durationSec: Double? = nil,
        state: JobState = .queued,
        attempt: Int = 0,
        nextAttemptAt: String? = nil,
        errorKind: String? = nil,
        errorMessage: String? = nil,
        workspacePath: String? = nil,
        detectedLang: String? = nil,
        updatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.batchID = batchID
        self.sequence = sequence
        self.sourceType = sourceType
        self.sourceURL = sourceURL
        self.sourcePath = sourcePath
        self.externalID = externalID
        self.title = title
        self.creator = creator
        self.durationSec = durationSec
        self.state = state.rawValue
        self.attempt = attempt
        self.nextAttemptAt = nextAttemptAt
        self.errorKind = errorKind
        self.errorMessage = errorMessage
        self.workspacePath = workspacePath
        self.detectedLang = detectedLang
        self.updatedAt = updatedAt
    }
}

public struct TranscriptSectionRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "transcript_section"
    
    public var jobID: String
    public var text: String
    public var segments: String?
    
    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case text
        case segments
    }
    
    public init(jobID: String, text: String, segments: String? = nil) {
        self.jobID = jobID
        self.text = text
        self.segments = segments
    }
}
