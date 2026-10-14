import Foundation

public struct YouTubeMetadata: Codable, Sendable {
    public let id: String
    public let title: String
    public let channel: String?
    public let duration: Double?
    public let ext: String?
}

public struct FetchedMedia: Sendable {
    public let localAudioURL: URL
    public let metadata: YouTubeMetadata
    
    public init(localAudioURL: URL, metadata: YouTubeMetadata) {
        self.localAudioURL = localAudioURL
        self.metadata = metadata
    }
}

public enum YTDLPErrorKind: String, Sendable, Codable {
    case videoUnavailable
    case ageRestricted
    case botCheck
    case network
    case noAudioFormat
    case unknown
}

public struct YTDLPError: Error, LocalizedError, Sendable {
    public let kind: YTDLPErrorKind
    public let message: String
    
    public init(kind: YTDLPErrorKind, message: String) {
        self.kind = kind
        self.message = message
    }
    
    public var errorDescription: String? {
        "[\(kind.rawValue)] \(message)"
    }
}

public final class YTDLPClient: Sendable {
    private let toolManager: ToolManager
    
    public init(toolManager: ToolManager = ToolManager()) {
        self.toolManager = toolManager
    }
    
    public func fetch(
        url: String,
        into workspace: URL,
        forceIPv4: Bool = false,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> FetchedMedia {
        try await toolManager.ensureToolsReady()
        
        let ytdlpURL = toolManager.ytdlpExecutableURL
        let denoURL = toolManager.denoExecutableURL
        
        let fm = FileManager.default
        if !fm.fileExists(atPath: workspace.path) {
            try fm.createDirectory(at: workspace, withIntermediateDirectories: true)
        }
        
        let outputTemplate = workspace.appendingPathComponent("input.%(ext)s").path
        
        var arguments = [
            "--no-playlist",
            "--newline",
            "--socket-timeout", "30",
            "--retries", "3",
            "-f", "bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/18",
            "-o", outputTemplate,
            "--no-simulate",
            "--print", "%(.{id,title,channel,duration,ext})#j",
            "--progress",
            "--progress-template", "download:%(progress._percent_str)s",
            "--js-runtimes", "deno:\(denoURL.path)"
        ]
        
        if forceIPv4 {
            arguments.append("-4")
        }
        arguments.append(url)
        
        let process = Process()
        process.executableURL = ytdlpURL
        process.arguments = arguments
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        // Progress and output tracker
        final class ProgressTracker: @unchecked Sendable {
            var fullStdout: String = ""
            var metadata: YouTubeMetadata?
            let onProgress: (@Sendable (Double) -> Void)?
            
            init(onProgress: (@Sendable (Double) -> Void)?) {
                self.onProgress = onProgress
            }
        }
        let tracker = ProgressTracker(onProgress: progress)
        
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            
            tracker.fullStdout.append(str)
            
            let lines = str.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                
                if trimmed.hasPrefix("download:") {
                    let percentStr = trimmed.dropFirst("download:".count).trimmingCharacters(in: .whitespaces)
                    let cleanNumber = percentStr.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
                    if let val = Double(cleanNumber) {
                        tracker.onProgress?(val / 100.0)
                    }
                }
            }
        }
        
        do {
            try process.run()
        } catch {
            throw YTDLPError(kind: .unknown, message: "yt-dlp süreci başlatılamadı: \(error.localizedDescription)")
        }
        
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
        
        guard process.terminationStatus == 0 else {
            let errorKind = classifyError(stderr: stderrText, exitCode: process.terminationStatus)
            throw YTDLPError(kind: errorKind, message: stderrText.isEmpty ? "Çıkış kodu: \(process.terminationStatus)" : stderrText)
        }
        
        // Extract JSON metadata from accumulated stdout
        let fullOutput = tracker.fullStdout
        if let startRange = fullOutput.range(of: "{"),
           let endRange = fullOutput.range(of: "}", options: .backwards),
           startRange.lowerBound < endRange.upperBound {
            let jsonSubstring = fullOutput[startRange.lowerBound..<endRange.upperBound]
            if let data = String(jsonSubstring).data(using: .utf8),
               let meta = try? JSONDecoder().decode(YouTubeMetadata.self, from: data) {
                tracker.metadata = meta
            }
        }
        
        // Look for the downloaded file in workspace
        let items = try fm.contentsOfDirectory(at: workspace, includingPropertiesForKeys: nil)
        guard let audioFile = items.first(where: { $0.lastPathComponent.hasPrefix("input.") }) else {
            throw YTDLPError(kind: .noAudioFormat, message: "İndirilen ses dosyası çalışma alanında bulunamadı.")
        }
        
        let resolvedMetadata = tracker.metadata ?? YouTubeMetadata(
            id: audioFile.deletingPathExtension().lastPathComponent,
            title: audioFile.deletingPathExtension().lastPathComponent,
            channel: nil,
            duration: nil,
            ext: audioFile.pathExtension
        )
        
        progress?(1.0)
        return FetchedMedia(localAudioURL: audioFile, metadata: resolvedMetadata)
    }
    
    private func classifyError(stderr: String, exitCode: Int32) -> YTDLPErrorKind {
        let lower = stderr.lowercased()
        if lower.contains("private video") || lower.contains("video unavailable") || lower.contains("has been removed") || lower.contains("this video is unavailable") {
            return .videoUnavailable
        }
        if lower.contains("sign in to confirm your age") || lower.contains("age-restricted") {
            return .ageRestricted
        }
        if lower.contains("sign in to confirm you’re not a bot") || lower.contains("bot") || lower.contains("429") {
            return .botCheck
        }
        if lower.contains("timed out") || lower.contains("network is unreachable") || lower.contains("temporary failure in name resolution") {
            return .network
        }
        if lower.contains("requested format is not available") || lower.contains("no audio") {
            return .noAudioFormat
        }
        return .unknown
    }
}
