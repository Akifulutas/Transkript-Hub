import Foundation
import whisper

public enum WhisperCppError: Error, LocalizedError {
    case modelNotFound(String)
    case contextInitializationFailed
    case transcriptionFailed(Int32)
    case emptyAudio
    
    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "Whisper model dosyası bulunamadı: \(path)"
        case .contextInitializationFailed:
            return "whisper_context başlatılamadı (Metal / bellek hatası)."
        case .transcriptionFailed(let code):
            return "whisper_full transkripsiyon hatası verdi (kod: \(code))."
        case .emptyAudio:
            return "Transkript edilecek ses verisi boş."
        }
    }
}

private final class WhisperContextBox: @unchecked Sendable {
    let pointer: OpaquePointer
    
    init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }
    
    deinit {
        whisper_free(pointer)
    }
}

public actor WhisperCppEngine: TranscriptionEngine {
    private let contextBox: WhisperContextBox
    private let modelPath: String
    private var lastUsedTime: Date = Date()
    
    public init(modelPath: String) throws {
        self.modelPath = modelPath
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw WhisperCppError.modelNotFound(modelPath)
        }
        
        var cparams = whisper_context_default_params()
        cparams.use_gpu = true // Metal acceleration on macOS Apple Silicon
        cparams.flash_attn = true
        
        guard let context = whisper_init_from_file_with_params(modelPath, cparams) else {
            throw WhisperCppError.contextInitializationFailed
        }
        self.contextBox = WhisperContextBox(context)
        Log.info("WhisperCppEngine Metal context successfully initialized: \(modelPath)")
    }
    
    public func transcribe(
        _ audio: PreparedAudio,
        options: TranscriptionOptions,
        progress: (@Sendable (Double) -> Void)? = nil,
        onSegment: (@Sendable (Segment) -> Void)? = nil,
        cancellationToken: TranscriptionCancellationToken? = nil
    ) async throws -> TranscriptResult {
        if cancellationToken?.isCancelled == true || Task.isCancelled {
            throw CancellationError()
        }

        let context = contextBox.pointer
        guard !audio.samples.isEmpty else {
            throw WhisperCppError.emptyAudio
        }
        
        lastUsedTime = Date()

        let sampleRate = AudioDecoder.targetSampleRate
        let workingSamples = AudioConditioner.condition(samples: audio.samples, sampleRate: sampleRate)
        let totalSampleCount = workingSamples.count
        let slices: [(offsetSeconds: Double, range: Range<Int>)]

        if options.useVAD {
            let rmsSegments = AudioVAD.detectSpeech(samples: workingSamples, sampleRate: sampleRate)
            if rmsSegments.isEmpty {
                progress?(1.0)
                return TranscriptResult(segments: [], detectedLanguage: Self.normalizeLanguage(options.language))
            }
            let rawSpeechSegments: [SpeechSegment]
            if let sileroSegments = SileroVAD.detectSpeech(
                samples: workingSamples,
                sampleRate: sampleRate,
                maxSpeechDurationSeconds: 28.0
            ), (!sileroSegments.isEmpty || totalSampleCount >= Int(sampleRate * 6.0)) {
                rawSpeechSegments = sileroSegments
            } else {
                rawSpeechSegments = rmsSegments
            }
            let speechSegments = Qwen3ASREngine.splitSpeechSegments(rawSpeechSegments, maxDuration: 28.0)
            if speechSegments.isEmpty {
                progress?(1.0)
                return TranscriptResult(segments: [], detectedLanguage: Self.normalizeLanguage(options.language))
            }
            var builtSlices: [(offsetSeconds: Double, range: Range<Int>)] = []
            builtSlices.reserveCapacity(speechSegments.count)
            for seg in speechSegments {
                let startIdx = max(0, min(totalSampleCount, Int((seg.start * sampleRate).rounded(.down))))
                let endIdx = max(startIdx, min(totalSampleCount, Int((seg.end * sampleRate).rounded(.up))))
                if endIdx > startIdx {
                    builtSlices.append((offsetSeconds: Double(startIdx) / sampleRate, range: startIdx..<endIdx))
                }
            }
            if builtSlices.isEmpty {
                progress?(1.0)
                return TranscriptResult(segments: [], detectedLanguage: Self.normalizeLanguage(options.language))
            }
            slices = builtSlices
        } else {
            slices = [(offsetSeconds: 0.0, range: 0..<totalSampleCount)]
        }

        final class ProgressTracker: @unchecked Sendable {
            private let lock = NSLock()
            private var lastProgress: Double = 0.0
            private let callback: (@Sendable (Double) -> Void)?

            init(_ callback: (@Sendable (Double) -> Void)?) {
                self.callback = callback
            }

            func report(_ value: Double) {
                guard let callback else { return }
                let clamped = min(1.0, max(0.0, value))
                lock.lock()
                let shouldEmit = clamped >= lastProgress
                if shouldEmit {
                    lastProgress = clamped
                }
                lock.unlock()
                if shouldEmit {
                    callback(clamped)
                }
            }
        }

        final class StreamCallbackBox: @unchecked Sendable {
            let progressTracker: ProgressTracker
            let onSegment: (@Sendable (Segment) -> Void)?
            let cancellationToken: TranscriptionCancellationToken?
            let segmentOffset: Double
            let processedSamples: Int
            let sliceSampleCount: Int
            let totalSpeechSamples: Int

            init(
                progressTracker: ProgressTracker,
                onSegment: (@Sendable (Segment) -> Void)?,
                cancellationToken: TranscriptionCancellationToken?,
                segmentOffset: Double,
                processedSamples: Int,
                sliceSampleCount: Int,
                totalSpeechSamples: Int
            ) {
                self.progressTracker = progressTracker
                self.onSegment = onSegment
                self.cancellationToken = cancellationToken
                self.segmentOffset = segmentOffset
                self.processedSamples = processedSamples
                self.sliceSampleCount = sliceSampleCount
                self.totalSpeechSamples = totalSpeechSamples
            }
        }

        let totalSpeechSamples = slices.reduce(0) { $0 + $1.range.count }
        let progressTracker = ProgressTracker(progress)
        var processedSamples = 0
        var allSegments: [Segment] = []
        var languageWeights: [String: Int] = [:]

        for slice in slices {
            if cancellationToken?.isCancelled == true || Task.isCancelled {
                throw CancellationError()
            }

            let sliceCount = slice.range.count
            let streamBox = StreamCallbackBox(
                progressTracker: progressTracker,
                onSegment: onSegment,
                cancellationToken: cancellationToken,
                segmentOffset: slice.offsetSeconds,
                processedSamples: processedSamples,
                sliceSampleCount: sliceCount,
                totalSpeechSamples: totalSpeechSamples
            )
            let retainedBox = Unmanaged.passRetained(streamBox)
            defer { retainedBox.release() }

            let result: Int32 = Self.withWhisperParams(options: options) { wparams in
                wparams.progress_callback = { _, _, progressInt, userData in
                    guard let ptr = userData else { return }
                    let box = Unmanaged<StreamCallbackBox>.fromOpaque(ptr).takeUnretainedValue()
                    let localRatio = min(1.0, max(0.0, Double(progressInt) / 100.0))
                    let totalSamples = max(1, box.totalSpeechSamples)
                    let globalRatio = (Double(box.processedSamples) + localRatio * Double(box.sliceSampleCount)) / Double(totalSamples)
                    box.progressTracker.report(globalRatio)
                }
                wparams.progress_callback_user_data = retainedBox.toOpaque()

                wparams.abort_callback = { userData in
                    guard let ptr = userData else { return false }
                    let box = Unmanaged<StreamCallbackBox>.fromOpaque(ptr).takeUnretainedValue()
                    return box.cancellationToken?.isCancelled ?? false
                }
                wparams.abort_callback_user_data = retainedBox.toOpaque()

                wparams.encoder_begin_callback = { _, _, userData in
                    guard let ptr = userData else { return true }
                    let box = Unmanaged<StreamCallbackBox>.fromOpaque(ptr).takeUnretainedValue()
                    if box.cancellationToken?.isCancelled == true {
                        return false
                    }
                    return true
                }
                wparams.encoder_begin_callback_user_data = retainedBox.toOpaque()

                if onSegment != nil {
                    wparams.new_segment_callback = { ctx, _, n_new, userData in
                        guard let ptr = userData, let ctx = ctx else { return }
                        let box = Unmanaged<StreamCallbackBox>.fromOpaque(ptr).takeUnretainedValue()
                        let total = whisper_full_n_segments(ctx)
                        let start = max(0, total - n_new)
                        let offset = box.segmentOffset
                        for i in start..<total {
                            let t0 = (Double(whisper_full_get_segment_t0(ctx, i)) / 100.0) + offset
                            let t1 = (Double(whisper_full_get_segment_t1(ctx, i)) / 100.0) + offset
                            let textPtr = whisper_full_get_segment_text(ctx, i)
                            let text = textPtr != nil ? String(cString: textPtr!) : ""
                            let noSpeechProb = whisper_full_get_segment_no_speech_prob(ctx, i)
                            var words = WhisperCppEngine.extractWords(from: ctx, segmentIndex: i, segmentStart: t0 - offset, segmentEnd: t1 - offset)
                            if offset != 0.0 && !words.isEmpty {
                                words = words.map {
                                    Word(text: $0.text, start: $0.start + offset, end: $0.end + offset, confidence: $0.confidence)
                                }
                            }
                            if words.isEmpty && !text.isEmpty {
                                words = Segment.interpolateWords(for: text, start: t0, end: t1)
                            }
                            let segment = Segment(start: t0, end: t1, text: text, speaker: nil, words: words, noSpeechProb: noSpeechProb)
                            box.onSegment?(segment)
                        }
                    }
                    wparams.new_segment_callback_user_data = retainedBox.toOpaque()
                }

                return workingSamples[slice.range].withUnsafeBufferPointer { bufferPtr -> Int32 in
                    whisper_full(context, wparams, bufferPtr.baseAddress, Int32(sliceCount))
                }
            }

            if cancellationToken?.isCancelled == true || Task.isCancelled {
                throw CancellationError()
            }

            guard result == 0 else {
                throw WhisperCppError.transcriptionFailed(result)
            }

            let nSegments = whisper_full_n_segments(context)
            let offset = slice.offsetSeconds
            for i in 0..<nSegments {
                let rawT0 = Double(whisper_full_get_segment_t0(context, i)) / 100.0
                let rawT1 = Double(whisper_full_get_segment_t1(context, i)) / 100.0
                let t0 = rawT0 + offset
                let t1 = rawT1 + offset
                let textPtr = whisper_full_get_segment_text(context, i)
                let text = textPtr != nil ? String(cString: textPtr!) : ""
                let noSpeechProb = whisper_full_get_segment_no_speech_prob(context, i)
                var words = Self.extractWords(from: context, segmentIndex: i, segmentStart: rawT0, segmentEnd: rawT1)
                if offset != 0.0 && !words.isEmpty {
                    words = words.map {
                        Word(text: $0.text, start: $0.start + offset, end: $0.end + offset, confidence: $0.confidence)
                    }
                }
                if words.isEmpty && !text.isEmpty {
                    words = Segment.interpolateWords(for: text, start: t0, end: t1)
                }
                allSegments.append(Segment(start: t0, end: t1, text: text, speaker: nil, words: words, noSpeechProb: noSpeechProb))
            }

            let langId = whisper_full_lang_id(context)
            if let langStrPtr = whisper_lang_str(langId) {
                let lang = String(cString: langStrPtr)
                languageWeights[lang, default: 0] += sliceCount
            }

            processedSamples += sliceCount
            progressTracker.report(Double(processedSamples) / Double(max(1, totalSpeechSamples)))
        }

        let detectedLang = languageWeights.max(by: { $0.value < $1.value })?.key
        progressTracker.report(1.0)
        return TranscriptResult(segments: allSegments, detectedLanguage: detectedLang)
    }

    // MARK: - Whisper Parameter Configuration

    nonisolated static func normalizeLanguage(_ language: String?) -> String? {
        guard let trimmed = language?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed.lowercased() != "auto" else {
            return nil
        }
        return trimmed.lowercased()
    }

    nonisolated static func withWhisperParams<R>(
        options: TranscriptionOptions,
        body: (inout whisper_full_params) throws -> R
    ) rethrows -> R {
        let strategy = options.beamSize > 1 ? WHISPER_SAMPLING_BEAM_SEARCH : WHISPER_SAMPLING_GREEDY
        var wparams = whisper_full_default_params(strategy)
        if options.beamSize > 1 {
            wparams.beam_search.beam_size = Int32(options.beamSize)
        }
        wparams.n_threads = Int32(max(1, options.threads))
        wparams.print_progress = false
        wparams.print_special = false
        wparams.print_realtime = false
        wparams.print_timestamps = false
        wparams.translate = false
        wparams.no_timestamps = false
        wparams.token_timestamps = options.tokenTimestamps
        wparams.no_context = options.noContext
        wparams.suppress_blank = options.suppressBlank
        wparams.suppress_nst = options.suppressNonSpeech
        wparams.no_speech_thold = options.noSpeechThreshold
        wparams.entropy_thold = options.entropyThreshold
        wparams.temperature = options.temperature
        wparams.temperature_inc = options.temperatureInc

        let normalizedLanguage = normalizeLanguage(options.language)

        let trimmedPrompt = options.initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrompt: String? = (trimmedPrompt?.isEmpty == false) ? trimmedPrompt : nil
        wparams.carry_initial_prompt = (normalizedPrompt != nil)

        func withOptionalCString<T>(_ string: String?, _ block: (UnsafePointer<CChar>?) throws -> T) rethrows -> T {
            if let string {
                return try string.withCString { ptr in
                    try block(ptr)
                }
            } else {
                return try block(nil)
            }
        }

        return try withOptionalCString(normalizedLanguage) { langPtr in
            wparams.language = langPtr
            return try withOptionalCString(normalizedPrompt) { promptPtr in
                wparams.initial_prompt = promptPtr
                return try body(&wparams)
            }
        }
    }
    
    // MARK: - Token Timestamps & Word Extraction
    
    public static func extractWords(
        from ctx: OpaquePointer,
        segmentIndex: Int32,
        segmentStart: Double,
        segmentEnd: Double
    ) -> [Word] {
        let nTokens = whisper_full_n_tokens(ctx, segmentIndex)
        guard nTokens > 0 else { return [] }
        
        let eot = whisper_token_eot(ctx)
        var words: [Word] = []
        
        var currentText = ""
        var currentStart = segmentStart
        var currentEnd = segmentEnd
        var currentConfidences: [Float] = []
        var hasActiveWord = false
        
        func flushCurrentWord() {
            guard hasActiveWord else { return }
            let trimmed = currentText.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                let avgConf = currentConfidences.isEmpty ? 1.0 : currentConfidences.reduce(0, +) / Float(currentConfidences.count)
                words.append(Word(
                    text: trimmed,
                    start: currentStart,
                    end: max(currentStart, currentEnd),
                    confidence: avgConf
                ))
            }
            currentText = ""
            currentConfidences.removeAll()
            hasActiveWord = false
        }
        
        for j in 0..<nTokens {
            let tokenData = whisper_full_get_token_data(ctx, segmentIndex, j)
            if tokenData.id >= eot { continue }
            
            guard let textPtr = whisper_full_get_token_text(ctx, segmentIndex, j) else { continue }
            let tokenStr = String(cString: textPtr)
            guard !tokenStr.isEmpty else { continue }
            
            if tokenStr.hasPrefix("[_") || tokenStr.hasPrefix("<|") || tokenStr.hasSuffix("|>") {
                continue
            }
            
            let t0Raw = whisper_full_get_token_t0(ctx, segmentIndex, j)
            let t1Raw = whisper_full_get_token_t1(ctx, segmentIndex, j)
            let tokenStart = t0Raw >= 0 ? Double(t0Raw) / 100.0 : segmentStart
            let tokenEnd = t1Raw >= 0 ? Double(t1Raw) / 100.0 : max(tokenStart, segmentEnd)
            let confidence = whisper_full_get_token_p(ctx, segmentIndex, j)
            
            let trimmed = tokenStr.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushCurrentWord()
                continue
            }
            
            let startsWithSpace = tokenStr.first?.isWhitespace == true
            if startsWithSpace || !hasActiveWord {
                flushCurrentWord()
                currentText = trimmed
                currentStart = tokenStart
                currentEnd = tokenEnd
                currentConfidences = [confidence]
                hasActiveWord = true
            } else {
                currentText.append(tokenStr)
                currentEnd = max(currentEnd, tokenEnd)
                currentConfidences.append(confidence)
            }
        }
        
        flushCurrentWord()
        return words
    }
}
