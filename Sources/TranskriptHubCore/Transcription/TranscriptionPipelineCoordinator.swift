import Foundation

public struct TranscriptionPipelineResult: Sendable {
    public let preparedAudio: PreparedAudio
    public let transcriptResult: TranscriptResult
    public let cleanedSegments: [Segment]
    public let formattedText: String
    public let srtText: String

    public init(
        preparedAudio: PreparedAudio,
        transcriptResult: TranscriptResult,
        cleanedSegments: [Segment],
        formattedText: String,
        srtText: String
    ) {
        self.preparedAudio = preparedAudio
        self.transcriptResult = transcriptResult
        self.cleanedSegments = cleanedSegments
        self.formattedText = formattedText
        self.srtText = srtText
    }
}

/// Thread-safe segment accumulator used during streaming segment callbacks.
public final class PipelineSegmentCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var segments: [Segment] = []

    public init() {}

    public func append(_ seg: Segment) -> [Segment] {
        lock.lock()
        defer { lock.unlock() }
        segments.append(seg)
        return segments
    }
}

/// Shared domain coordinator that unifies audio decoding, ASR engine execution,
/// deterministic post-processing (`TranscriptPostProcessor`), and SRT cue generation
/// across the macOS GUI (`AppViewModel`), background `JobManager`, and `transkripthub-cli`.
public struct TranscriptionPipelineCoordinator: Sendable {
    private let audioDecoder: AudioDecoder
    private let postProcessor: TranscriptPostProcessor

    public init(
        audioDecoder: AudioDecoder = AudioDecoder(),
        postProcessor: TranscriptPostProcessor = TranscriptPostProcessor()
    ) {
        self.audioDecoder = audioDecoder
        self.postProcessor = postProcessor
    }

    public func execute(
        audioFileURL: URL,
        engine: any TranscriptionEngine,
        transcriptionOptions: TranscriptionOptions,
        postProcessorOptions: PostProcessorOptions = PostProcessorOptions(),
        progress: (@Sendable (Double) -> Void)? = nil,
        onLiveTranscript: (@Sendable (String, Segment) -> Void)? = nil,
        cancellationToken: TranscriptionCancellationToken? = nil
    ) async throws -> TranscriptionPipelineResult {
        if cancellationToken?.isCancelled == true || Task.isCancelled {
            throw CancellationError()
        }

        let decoder = self.audioDecoder
        let prepared = try await Task.detached(priority: .userInitiated) {
            try decoder.decode(fileURL: audioFileURL)
        }.value

        return try await execute(
            preparedAudio: prepared,
            engine: engine,
            transcriptionOptions: transcriptionOptions,
            postProcessorOptions: postProcessorOptions,
            progress: progress,
            onLiveTranscript: onLiveTranscript,
            cancellationToken: cancellationToken
        )
    }

    public func execute(
        preparedAudio: PreparedAudio,
        engine: any TranscriptionEngine,
        transcriptionOptions: TranscriptionOptions,
        postProcessorOptions: PostProcessorOptions = PostProcessorOptions(),
        progress: (@Sendable (Double) -> Void)? = nil,
        onLiveTranscript: (@Sendable (String, Segment) -> Void)? = nil,
        cancellationToken: TranscriptionCancellationToken? = nil
    ) async throws -> TranscriptionPipelineResult {
        if cancellationToken?.isCancelled == true || Task.isCancelled {
            throw CancellationError()
        }

        let collector = PipelineSegmentCollector()
        let processor = self.postProcessor
        let segmentCallback: (@Sendable (Segment) -> Void)?
        if let onLive = onLiveTranscript {
            segmentCallback = { seg in
                guard cancellationToken?.isCancelled != true else { return }
                let accumulated = collector.append(seg)
                let liveText = processor.process(segments: accumulated, options: postProcessorOptions)
                onLive(liveText, seg)
            }
        } else {
            segmentCallback = nil
        }

        let result = try await engine.transcribe(
            preparedAudio,
            options: transcriptionOptions,
            progress: progress,
            onSegment: segmentCallback,
            cancellationToken: cancellationToken
        )

        let cleanedSegments = processor.processSegments(segments: result.segments, options: postProcessorOptions)
        let formattedText = processor.process(segments: result.segments, options: postProcessorOptions)
        let srtText = SRTFormatter.format(segments: cleanedSegments)

        return TranscriptionPipelineResult(
            preparedAudio: preparedAudio,
            transcriptResult: result,
            cleanedSegments: cleanedSegments,
            formattedText: formattedText,
            srtText: srtText
        )
    }
}
