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
    
    public func downloadModel(
        _ model: WhisperModel,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        try ensureDirectoryExists()
        let destination = localURL(for: model)
        if FileManager.default.fileExists(atPath: destination.path) {
            progress?(1.0)
            return destination
        }
        
        Log.info("Model indiriliyor: \(model.filename) -> \(destination.path)")
        let (tempURL, response) = try await URLSession.shared.download(from: model.downloadURL)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "ModelManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model indirilemedi (HTTP hata)."])
        }
        
        // Atomic move
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        Log.info("Model başarıyla kaydedildi: \(destination.path)")
        progress?(1.0)
        return destination
    }
}
