import Foundation

public protocol TranscriptionEngine: Sendable {
    func transcribe(
        _ audio: PreparedAudio,
        options: TranscriptionOptions,
        progress: (@Sendable (Double) -> Void)?,
        onSegment: (@Sendable (Segment) -> Void)?
    ) async throws -> TranscriptResult
}

extension TranscriptionEngine {
    public func transcribe(
        _ audio: PreparedAudio,
        options: TranscriptionOptions,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> TranscriptResult {
        try await transcribe(audio, options: options, progress: progress, onSegment: nil)
    }
}
