import Foundation

public final class TranscriptionCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled: Bool = false
    
    public init() {}
    
    public var isCancelled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _cancelled
        }
        set {
            lock.lock()
            _cancelled = newValue
            lock.unlock()
        }
    }
    
    public func cancel() {
        lock.lock()
        _cancelled = true
        lock.unlock()
    }
}

public protocol TranscriptionEngine: Sendable {
    func transcribe(
        _ audio: PreparedAudio,
        options: TranscriptionOptions,
        progress: (@Sendable (Double) -> Void)?,
        onSegment: (@Sendable (Segment) -> Void)?,
        cancellationToken: TranscriptionCancellationToken?
    ) async throws -> TranscriptResult
}

extension TranscriptionEngine {
    public func transcribe(
        _ audio: PreparedAudio,
        options: TranscriptionOptions,
        progress: (@Sendable (Double) -> Void)? = nil,
        onSegment: (@Sendable (Segment) -> Void)? = nil,
        cancellationToken: TranscriptionCancellationToken? = nil
    ) async throws -> TranscriptResult {
        try await transcribe(audio, options: options, progress: progress, onSegment: onSegment, cancellationToken: cancellationToken)
    }
}
