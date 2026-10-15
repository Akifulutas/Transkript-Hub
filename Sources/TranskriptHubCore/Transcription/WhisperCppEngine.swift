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
        onSegment: (@Sendable (Segment) -> Void)? = nil
    ) async throws -> TranscriptResult {
        let context = contextBox.pointer
        guard !audio.samples.isEmpty else {
            throw WhisperCppError.emptyAudio
        }
        
        lastUsedTime = Date()
        
        // Sampling strategy: Greedy by default, fast and accurate
        var wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        wparams.n_threads = Int32(options.threads)
        wparams.print_progress = false
        wparams.print_special = false
        wparams.print_realtime = false
        wparams.print_timestamps = false
        wparams.translate = false
        wparams.no_timestamps = false
        wparams.token_timestamps = options.tokenTimestamps
        
        // Stream callback wrapper for progress and live segments
        final class StreamCallbackBox: @unchecked Sendable {
            let progress: (@Sendable (Double) -> Void)?
            let onSegment: (@Sendable (Segment) -> Void)?
            init(progress: (@Sendable (Double) -> Void)?, onSegment: (@Sendable (Segment) -> Void)?) {
                self.progress = progress
                self.onSegment = onSegment
            }
        }
        let streamBox = StreamCallbackBox(progress: progress, onSegment: onSegment)
        let retainedBox = Unmanaged.passRetained(streamBox)
        defer { retainedBox.release() }
        
        wparams.progress_callback = { ctx, state, progressInt, userData in
            guard let ptr = userData else { return }
            let box = Unmanaged<StreamCallbackBox>.fromOpaque(ptr).takeUnretainedValue()
            let ratio = Double(progressInt) / 100.0
            box.progress?(ratio)
        }
        wparams.progress_callback_user_data = retainedBox.toOpaque()
        
        if onSegment != nil {
            wparams.new_segment_callback = { ctx, state, n_new, userData in
                guard let ptr = userData, let ctx = ctx else { return }
                let box = Unmanaged<StreamCallbackBox>.fromOpaque(ptr).takeUnretainedValue()
                let total = whisper_full_n_segments(ctx)
                let start = max(0, total - n_new)
                for i in start..<total {
                    let t0 = Double(whisper_full_get_segment_t0(ctx, i)) / 100.0
                    let t1 = Double(whisper_full_get_segment_t1(ctx, i)) / 100.0
                    let textPtr = whisper_full_get_segment_text(ctx, i)
                    let text = textPtr != nil ? String(cString: textPtr!) : ""
                    var words = WhisperCppEngine.extractWords(from: ctx, segmentIndex: i, segmentStart: t0, segmentEnd: t1)
                    if words.isEmpty && !text.isEmpty {
                        words = Segment.interpolateWords(for: text, start: t0, end: t1)
                    }
                    let segment = Segment(start: t0, end: t1, text: text, speaker: nil, words: words)
                    box.onSegment?(segment)
                }
            }
            wparams.new_segment_callback_user_data = retainedBox.toOpaque()
        }
        
        // Language
        var langCString: UnsafeMutablePointer<CChar>? = nil
        if let lang = options.language, !lang.isEmpty, lang != "auto" {
            langCString = strdup(lang)
            wparams.language = UnsafePointer(langCString)
        } else {
            wparams.language = nil // Auto-detect
        }
        defer {
            if let ptr = langCString { free(ptr) }
        }
        
        // Initial Prompt
        var promptCString: UnsafeMutablePointer<CChar>? = nil
        if let prompt = options.initialPrompt, !prompt.isEmpty {
            promptCString = strdup(prompt)
            wparams.initial_prompt = UnsafePointer(promptCString)
        }
        defer {
            if let ptr = promptCString { free(ptr) }
        }
        
        let samples = audio.samples
        let result = samples.withUnsafeBufferPointer { bufferPtr -> Int32 in
            whisper_full(context, wparams, bufferPtr.baseAddress, Int32(samples.count))
        }
        
        guard result == 0 else {
            throw WhisperCppError.transcriptionFailed(result)
        }
        
        // Extract segments
        let nSegments = whisper_full_n_segments(context)
        var segments: [Segment] = []
        segments.reserveCapacity(Int(nSegments))
        
        for i in 0..<nSegments {
            let t0 = Double(whisper_full_get_segment_t0(context, i)) / 100.0
            let t1 = Double(whisper_full_get_segment_t1(context, i)) / 100.0
            let textPtr = whisper_full_get_segment_text(context, i)
            let text = textPtr != nil ? String(cString: textPtr!) : ""
            var words = Self.extractWords(from: context, segmentIndex: i, segmentStart: t0, segmentEnd: t1)
            if words.isEmpty && !text.isEmpty {
                words = Segment.interpolateWords(for: text, start: t0, end: t1)
            }
            segments.append(Segment(start: t0, end: t1, text: text, speaker: nil, words: words))
        }
        
        // Detect language
        let langId = whisper_full_lang_id(context)
        let langStrPtr = whisper_lang_str(langId)
        let detectedLang = langStrPtr != nil ? String(cString: langStrPtr!) : nil
        
        progress?(1.0)
        return TranscriptResult(segments: segments, detectedLanguage: detectedLang)
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
