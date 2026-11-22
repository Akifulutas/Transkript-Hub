import Foundation

public struct YouTubeChapter: Codable, Sendable, Hashable {
    public let startTime: Double
    public let endTime: Double?
    public let title: String
    
    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case title
    }
    
    public init(startTime: Double, endTime: Double? = nil, title: String) {
        self.startTime = startTime
        self.endTime = endTime
        self.title = title
    }
}

public struct YouTubeHeatmapPoint: Codable, Sendable, Hashable {
    public let startTime: Double
    public let endTime: Double
    public let value: Double
    
    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case value
    }
    
    public init(startTime: Double, endTime: Double, value: Double) {
        self.startTime = startTime
        self.endTime = endTime
        self.value = value
    }
}

public struct YouTubeComment: Codable, Sendable, Hashable {
    public let author: String?
    public let text: String?
    public let likeCount: Int?
    public let isPinned: Bool?
    public let isUploader: Bool?
    public let isFavorited: Bool?
    
    enum CodingKeys: String, CodingKey {
        case author
        case text
        case likeCount = "like_count"
        case isPinned = "is_pinned"
        case isUploader = "is_uploader"
        case isFavorited = "is_favorited"
    }
    
    public init(
        author: String? = nil,
        text: String? = nil,
        likeCount: Int? = nil,
        isPinned: Bool? = nil,
        isUploader: Bool? = nil,
        isFavorited: Bool? = nil
    ) {
        self.author = author
        self.text = text
        self.likeCount = likeCount
        self.isPinned = isPinned
        self.isUploader = isUploader
        self.isFavorited = isFavorited
    }
}

public struct YouTubeMetadata: Codable, Sendable {
    public let id: String
    public let title: String
    public let channel: String?
    public let channelURL: String?
    public let channelFollowerCount: Int?
    public let uploadDate: String?
    public let duration: Double?
    public let viewCount: Int?
    public let likeCount: Int?
    public let commentCount: Int?
    public let liveStatus: String?
    public let categories: [String]?
    public let tags: [String]?
    public let ext: String?
    public let description: String?
    public let chapters: [YouTubeChapter]?
    public let heatmap: [YouTubeHeatmapPoint]?
    public let comments: [YouTubeComment]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case channel
        case channelURL = "channel_url"
        case channelFollowerCount = "channel_follower_count"
        case uploadDate = "upload_date"
        case duration
        case viewCount = "view_count"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case liveStatus = "live_status"
        case categories
        case tags
        case ext
        case description
        case chapters
        case heatmap
        case comments
    }
    
    public init(
        id: String,
        title: String,
        channel: String?,
        channelURL: String? = nil,
        channelFollowerCount: Int? = nil,
        uploadDate: String? = nil,
        duration: Double?,
        viewCount: Int? = nil,
        likeCount: Int? = nil,
        commentCount: Int? = nil,
        liveStatus: String? = nil,
        categories: [String]? = nil,
        tags: [String]? = nil,
        ext: String?,
        description: String? = nil,
        chapters: [YouTubeChapter]? = nil,
        heatmap: [YouTubeHeatmapPoint]? = nil,
        comments: [YouTubeComment]? = nil
    ) {
        self.id = id
        self.title = title
        self.channel = channel
        self.channelURL = channelURL
        self.channelFollowerCount = channelFollowerCount
        self.uploadDate = uploadDate
        self.duration = duration
        self.viewCount = viewCount
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.liveStatus = liveStatus
        self.categories = categories
        self.tags = tags
        self.ext = ext
        self.description = description
        self.chapters = chapters
        self.heatmap = heatmap
        self.comments = comments
    }
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
        } else {
            let existingFiles = (try? fm.contentsOfDirectory(at: workspace, includingPropertiesForKeys: nil)) ?? []
            for f in existingFiles where f.lastPathComponent.hasPrefix("input.") {
                try? fm.removeItem(at: f)
            }
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
            "--write-comments",
            "--extractor-args", "youtube:max_comments=15,all,0,0;comment_sort=top",
            "--print", "%(.{id,title,channel,channel_url,channel_follower_count,upload_date,duration,view_count,like_count,comment_count,live_status,categories,tags,ext,description,chapters,heatmap,comments})j",
            "--progress",
            "--progress-template", "download:%(progress._percent_str)s"
        ]
        if toolManager.isDenoReady() {
            arguments.append(contentsOf: ["--js-runtimes", "deno:\(denoURL.path)"])
        }
        
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
            private let lock = NSLock()
            private var _fullStdout: String = ""
            private var _fullStderr: String = ""
            private var _metadata: YouTubeMetadata?
            let onProgress: (@Sendable (Double) -> Void)?
            
            init(onProgress: (@Sendable (Double) -> Void)?) {
                self.onProgress = onProgress
            }
            
            var fullStdout: String {
                lock.lock()
                defer { lock.unlock() }
                return _fullStdout
            }
            
            func appendStdout(_ str: String) {
                lock.lock()
                _fullStdout.append(str)
                lock.unlock()
            }
            
            var fullStderr: String {
                lock.lock()
                defer { lock.unlock() }
                return _fullStderr
            }
            
            func appendStderr(_ str: String) {
                lock.lock()
                _fullStderr.append(str)
                lock.unlock()
            }
            
            var metadata: YouTubeMetadata? {
                get {
                    lock.lock()
                    defer { lock.unlock() }
                    return _metadata
                }
                set {
                    lock.lock()
                    _metadata = newValue
                    lock.unlock()
                }
            }
        }
        let tracker = ProgressTracker(onProgress: progress)
        
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            
            tracker.appendStdout(str)
            
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
        
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            tracker.appendStderr(str)
        }
        
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    process.terminationHandler = { _ in
                        continuation.resume()
                    }
                    do {
                        try process.run()
                    } catch {
                        process.terminationHandler = nil
                        continuation.resume(throwing: error)
                    }
                }
            } onCancel: {
                if process.isRunning {
                    process.terminate()
                }
            }
        } catch is CancellationError {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            if process.isRunning {
                process.terminate()
            }
            throw CancellationError()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw YTDLPError(kind: .unknown, message: "yt-dlp süreci başlatılamadı: \(error.localizedDescription)")
        }
        
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        
        if let remOut = try? stdoutPipe.fileHandleForReading.readToEnd(),
           let str = String(data: remOut, encoding: .utf8), !str.isEmpty {
            tracker.appendStdout(str)
        }
        if let remErr = try? stderrPipe.fileHandleForReading.readToEnd(),
           let str = String(data: remErr, encoding: .utf8), !str.isEmpty {
            tracker.appendStderr(str)
        }
        
        if Task.isCancelled {
            throw CancellationError()
        }
        
        let stderrText = tracker.fullStderr
        
        guard process.terminationStatus == 0 else {
            let errorKind = classifyError(stderr: stderrText, exitCode: process.terminationStatus)
            throw YTDLPError(kind: errorKind, message: stderrText.isEmpty ? "Çıkış kodu: \(process.terminationStatus)" : stderrText)
        }
        
        // Look for the downloaded audio file in workspace (strictly excluding .info.json & sidecar files)
        let items = try fm.contentsOfDirectory(at: workspace, includingPropertiesForKeys: nil)
        let nonAudioExts: Set<String> = ["json", "part", "ytdl", "txt", "description", "vtt", "srt", "jpg", "jpeg", "png", "webp"]
        
        // Extract JSON metadata from accumulated stdout, or fall back to sidecar input.info.json if present
        let fullOutput = tracker.fullStdout
        if let meta = Self.parseMetadata(from: fullOutput) {
            tracker.metadata = meta
        } else if let infoJSONURL = items.first(where: { $0.lastPathComponent.hasSuffix(".info.json") }),
                  let data = try? Data(contentsOf: infoJSONURL),
                  let meta = try? JSONDecoder().decode(YouTubeMetadata.self, from: data) {
            tracker.metadata = meta
        }
        
        guard let audioFile = items.first(where: {
            $0.lastPathComponent.hasPrefix("input.") && !nonAudioExts.contains($0.pathExtension.lowercased())
        }) else {
            throw YTDLPError(kind: .noAudioFormat, message: "İndirilen ses dosyası çalışma alanında bulunamadı.")
        }
        
        let resolvedMetadata = tracker.metadata ?? YouTubeMetadata(
            id: audioFile.deletingPathExtension().lastPathComponent,
            title: audioFile.deletingPathExtension().lastPathComponent,
            channel: nil,
            duration: nil,
            ext: audioFile.pathExtension,
            description: nil
        )
        
        progress?(1.0)
        return FetchedMedia(localAudioURL: audioFile, metadata: resolvedMetadata)
    }
    
    /// Extracts `YouTubeMetadata` JSON emitted by `yt-dlp --print "%(.{...})j"`.
    /// Prefers compact single-line JSON (safe when descriptions contain braces or progress lines interleave)
    /// and falls back to multi-line `{ ... }` JSON decoding.
    public static func parseMetadata(from stdout: String) -> YouTubeMetadata? {
        let lines = stdout.components(separatedBy: .newlines)
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{"), trimmed.hasSuffix("}"),
               let data = trimmed.data(using: .utf8),
               let meta = try? JSONDecoder().decode(YouTubeMetadata.self, from: data) {
                return meta
            }
        }
        if let startRange = stdout.range(of: "{"),
           let endRange = stdout.range(of: "}", options: .backwards),
           startRange.lowerBound < endRange.upperBound {
            let jsonSubstring = stdout[startRange.lowerBound..<endRange.upperBound]
            if let data = String(jsonSubstring).data(using: .utf8),
               let meta = try? JSONDecoder().decode(YouTubeMetadata.self, from: data) {
                return meta
            }
        }
        return nil
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
    
    // MARK: - Playlist & Channel Resolution
    public func resolvePlaylistOrChannel(
        url: String,
        maxVideos: Int? = nil
    ) async throws -> [PlaylistVideoEntry] {
        try await toolManager.ensureToolsReady()
        let ytdlpURL = toolManager.ytdlpExecutableURL
        
        var arguments = [
            "--flat-playlist",
            "--print", "%(id)s\t%(title)s"
        ]
        
        if let max = maxVideos, max > 0 {
            arguments.append(contentsOf: ["--playlist-end", "\(max)"])
        }
        
        arguments.append(url)
        
        let process = Process()
        process.executableURL = ytdlpURL
        process.arguments = arguments
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        try process.run()
        
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        
        async let stdoutTask = Task.detached {
            stdoutHandle.readDataToEndOfFile()
        }.value
        
        async let stderrTask = Task.detached {
            stderrHandle.readDataToEndOfFile()
        }.value
        
        let (stdoutData, stderrData) = await (stdoutTask, stderrTask)
        process.waitUntilExit()
        
        let output = String(data: stdoutData, encoding: .utf8) ?? ""
        var entries: [PlaylistVideoEntry] = []
        
        for line in output.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: "\t")
            if parts.count >= 2 {
                let id = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !id.isEmpty && URLParser.isValidID(id) {
                    entries.append(PlaylistVideoEntry(id: id, title: title.isEmpty ? "Video (\(id))" : title))
                }
            } else if parts.count == 1 {
                let id = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                if !id.isEmpty && URLParser.isValidID(id) {
                    entries.append(PlaylistVideoEntry(id: id, title: "Video (\(id))"))
                }
            }
        }
        
        if entries.isEmpty && process.terminationStatus != 0 {
            let errStr = String(data: stderrData, encoding: .utf8) ?? ""
            let kind = classifyError(stderr: errStr, exitCode: process.terminationStatus)
            throw YTDLPError(kind: kind, message: "Oynatma listesi veya kanal çözümlenemedi: \(errStr.prefix(200))")
        }
        
        return entries
    }
}

public struct PlaylistVideoEntry: Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let url: String
    
    public init(id: String, title: String) {
        self.id = id
        self.title = title
        self.url = "https://www.youtube.com/watch?v=\(id)"
    }
}

