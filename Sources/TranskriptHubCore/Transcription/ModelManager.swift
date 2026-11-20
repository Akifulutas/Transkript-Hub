import Foundation

public enum TranscriptionEngineKind: String, Sendable, Equatable {
    case whisperCpp
    case qwen3ASR
}

public enum WhisperModel: String, Sendable, CaseIterable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case medium = "medium"
    case largeV3Q5 = "large-v3-q5_0"
    case largeV3 = "large-v3"
    case largeV3Turbo = "large-v3-turbo"
    case largeV3TurboQ5 = "large-v3-turbo-q5_0"
    case qwen3ASR06B = "qwen3-asr-0.6b"
    case qwen3ASR17B = "qwen3-asr-1.7b"
    
    public var engineKind: TranscriptionEngineKind {
        switch self {
        case .qwen3ASR06B, .qwen3ASR17B:
            return .qwen3ASR
        default:
            return .whisperCpp
        }
    }
    
    public var isDirectoryModel: Bool {
        engineKind == .qwen3ASR
    }
    
    public var filename: String {
        switch self {
        case .largeV3TurboQ5:
            return "ggml-large-v3-turbo-q5_0.bin"
        case .largeV3Q5:
            return "ggml-large-v3-q5_0.bin"
        case .qwen3ASR06B, .qwen3ASR17B:
            return rawValue
        default:
            return "ggml-\(rawValue).bin"
        }
    }
    
    public var requiredDirectoryFiles: [String] {
        switch self {
        case .qwen3ASR06B:
            return [
                "config.json",
                "generation_config.json",
                "model.safetensors",
                "vocab.json",
                "merges.txt"
            ]
        case .qwen3ASR17B:
            return [
                "config.json",
                "generation_config.json",
                "model.safetensors.index.json",
                "model-00001-of-00002.safetensors",
                "model-00002-of-00002.safetensors",
                "vocab.json",
                "merges.txt"
            ]
        default:
            return []
        }
    }
    
    public var downloadURL: URL {
        switch self {
        case .largeV3TurboQ5:
            return URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")!
        case .largeV3Q5:
            return URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-q5_0.bin")!
        case .qwen3ASR06B:
            return URL(string: "https://huggingface.co/Qwen/Qwen3-ASR-0.6B/resolve/main/model.safetensors")!
        case .qwen3ASR17B:
            return URL(string: "https://huggingface.co/Qwen/Qwen3-ASR-1.7B/resolve/main/model-00001-of-00002.safetensors")!
        default:
            return URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
        }
    }
    
    public func directoryFileDownloadURL(fileName: String) -> URL {
        let repo = (self == .qwen3ASR06B) ? "Qwen/Qwen3-ASR-0.6B" : "Qwen/Qwen3-ASR-1.7B"
        return URL(string: "https://huggingface.co/\(repo)/resolve/main/\(fileName)")!
    }
    
    public var displayName: String {
        switch self {
        case .largeV3: return "Large-v3 (Full 32-Layer)"
        case .largeV3Q5: return "Large-v3 (Q5_0)"
        case .largeV3Turbo: return "Large-v3-Turbo"
        case .largeV3TurboQ5: return "Large-v3-Turbo (Q5_0)"
        case .qwen3ASR06B: return "Qwen3-ASR-0.6B"
        case .qwen3ASR17B: return "Qwen3-ASR-1.7B"
        case .small: return "Small"
        case .base: return "Base"
        case .tiny: return "Tiny"
        case .medium: return "Medium"
        }
    }
}

public final class ModelManager: Sendable {
    public let modelsDirectory: URL
    
    public init(modelsDirectory: URL? = nil) {
        if let dir = modelsDirectory {
            self.modelsDirectory = dir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.modelsDirectory = appSupport.appendingPathComponent("TranskriptHub/Models", isDirectory: true)
        }
    }
    
    public func ensureDirectoryExists() throws {
        if !FileManager.default.fileExists(atPath: modelsDirectory.path) {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        }
    }
    
    public func localURL(for model: WhisperModel) -> URL {
        modelsDirectory.appendingPathComponent(model.filename, isDirectory: model.isDirectoryModel)
    }
    
    public func isModelDownloaded(_ model: WhisperModel) -> Bool {
        let url = localURL(for: model)
        if model.isDirectoryModel {
            let fm = FileManager.default
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                return false
            }
            let criticalFiles = model.requiredDirectoryFiles.filter { $0 != "generation_config.json" }
            for file in criticalFiles {
                let fileURL = url.appendingPathComponent(file)
                guard fm.fileExists(atPath: fileURL.path),
                      let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
                      (attrs[.size] as? Int64 ?? 0) > 0 else {
                    return false
                }
            }
            return true
        }
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    public func downloadedModels() -> [WhisperModel] {
        WhisperModel.allCases.filter { isModelDownloaded($0) }
    }
    
    public func deleteModel(_ model: WhisperModel) throws {
        let destination = localURL(for: model)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
            Log.info("Model deleted: \(destination.path)")
        }
    }
    
    public func downloadModelWithDetails(
        _ model: WhisperModel,
        onProgress: (@Sendable (Double, Int64, Int64) -> Void)? = nil
    ) async throws -> URL {
        try ensureDirectoryExists()
        let destination = localURL(for: model)
        if isModelDownloaded(model) {
            onProgress?(1.0, 1, 1)
            return destination
        }
        
        if model.isDirectoryModel {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let files = model.requiredDirectoryFiles
            for (index, fileName) in files.enumerated() {
                let targetFile = destination.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: targetFile.path),
                   let attrs = try? FileManager.default.attributesOfItem(atPath: targetFile.path),
                   (attrs[.size] as? Int64 ?? 0) > 0 {
                    continue
                }
                let fileURL = model.directoryFileDownloadURL(fileName: fileName)
                let fileCount = Double(max(1, files.count))
                let baseFrac = Double(index) / fileCount
                let delegate = DownloadProgressDelegate()
                delegate.onProgress = { frac, written, expected in
                    let combined = min(1.0, baseFrac + (frac / fileCount))
                    onProgress?(combined, written, expected)
                }
                let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
                defer { session.finishTasksAndInvalidate() }
                let tempURL: URL = try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        delegate.continuation = continuation
                        let task = session.downloadTask(with: fileURL)
                        delegate.setTask(task)
                        task.resume()
                    }
                } onCancel: {
                    delegate.cancel()
                }
                if FileManager.default.fileExists(atPath: targetFile.path) {
                    try FileManager.default.removeItem(at: targetFile)
                }
                try FileManager.default.moveItem(at: tempURL, to: targetFile)
            }
            onProgress?(1.0, 1, 1)
            return destination
        }
        
        Log.info("Downloading model: \(model.filename) -> \(destination.path)")
        
        let delegate = DownloadProgressDelegate()
        delegate.onProgress = onProgress
        
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        
        let tempURL: URL = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.continuation = continuation
                let task = session.downloadTask(with: model.downloadURL)
                delegate.setTask(task)
                task.resume()
            }
        } onCancel: {
            delegate.cancel()
        }
        
        // Atomic move
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        Log.info("Model successfully saved: \(destination.path)")
        onProgress?(1.0, 1, 1)
        return destination
    }
    
    public func downloadModel(
        _ model: WhisperModel,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        try await downloadModelWithDetails(model) { frac, _, _ in
            progress?(frac)
        }
    }
}

// MARK: - Download Progress Delegate
final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    var onProgress: (@Sendable (Double, Int64, Int64) -> Void)?
    var continuation: CheckedContinuation<URL, Error>?
    private var downloadTask: URLSessionDownloadTask?
    private var hasResumed = false
    private let lock = NSLock()
    
    func setTask(_ task: URLSessionDownloadTask) {
        lock.lock()
        defer { lock.unlock() }
        self.downloadTask = task
    }
    
    func cancel() {
        lock.lock()
        let task = downloadTask
        lock.unlock()
        task?.cancel()
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let fraction = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        onProgress?(fraction, totalBytesWritten, totalBytesExpectedToWrite)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let tempDest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bin")
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true
        do {
            try FileManager.default.moveItem(at: location, to: tempDest)
            continuation?.resume(returning: tempDest)
        } catch {
            continuation?.resume(throwing: error)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            lock.lock()
            defer { lock.unlock() }
            guard !hasResumed else { return }
            hasResumed = true
            continuation?.resume(throwing: error)
        }
    }
}
