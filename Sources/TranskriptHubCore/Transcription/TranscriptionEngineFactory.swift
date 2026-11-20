import Foundation

public enum TranscriptionEngineFactory: Sendable {
    /// Creates the appropriate `TranscriptionEngine` (`WhisperCppEngine` or `Qwen3ASREngine`)
    /// based on the selected `WhisperModel` or by inspecting the model path on disk.
    public static func makeEngine(model: WhisperModel, modelPath: String) throws -> any TranscriptionEngine {
        switch model.engineKind {
        case .whisperCpp:
            return try WhisperCppEngine(modelPath: modelPath)
        case .qwen3ASR:
            return try Qwen3ASREngine(modelPath: modelPath)
        }
    }

    public static func makeEngine(modelPath: String) throws -> any TranscriptionEngine {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: modelPath, isDirectory: &isDir)
        let lower = (modelPath as NSString).lastPathComponent.lowercased()
        if (exists && isDir.boolValue) || lower.contains("qwen") || lower.hasSuffix(".safetensors") {
            return try Qwen3ASREngine(modelPath: modelPath)
        }
        return try WhisperCppEngine(modelPath: modelPath)
    }
}
