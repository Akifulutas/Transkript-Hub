import Foundation

public enum WhisperModel: String, Sendable, CaseIterable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case medium = "medium"
    case largeV3Turbo = "large-v3-turbo"
    case largeV3TurboQ5 = "large-v3-turbo-q5_0"
    
    public var filename: String {
        switch self {
        case .largeV3TurboQ5:
            return "ggml-large-v3-turbo-q5_0.bin"
        default:
            return "ggml-\(rawValue).bin"
        }
    }
    
    public var downloadURL: URL {
        switch self {
        case .largeV3TurboQ5:
            return URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")!
        default:
            return URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
        }
    }
    
    public var displayName: String {
        switch self {
        case .largeV3Turbo: return "Large-v3-Turbo"
        case .largeV3TurboQ5: return "Large-v3-Turbo (Q5_0)"
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
        modelsDirectory.appendingPathComponent(model.filename)
    }
    
    public func isModelDownloaded(_ model: WhisperModel) -> Bool {
        let url = localURL(for: model)
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
        if FileManager.default.fileExists(atPath: destination.path) {
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
