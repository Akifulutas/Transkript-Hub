import Foundation

public protocol TranscriptionEngine: Sendable {
    func transcribe(
        _ audio: PreparedAudio,
        options: TranscriptionOptions,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> TranscriptResult
}
