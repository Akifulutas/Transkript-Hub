import Foundation

public struct ParsedYouTubeVideo: Sendable, Equatable, Hashable {
    public let videoID: String
    public let canonicalURL: String
    
    public init(videoID: String) {
        self.videoID = videoID
        self.canonicalURL = "https://www.youtube.com/watch?v=\(videoID)"
    }
}

public enum YouTubeLinkType: Sendable, Equatable, Hashable {
    case singleVideo(ParsedYouTubeVideo)
    case playlist(url: String, playlistID: String, videoID: String?)
    case channel(url: String, channelIdentifier: String)
    
    public var isBatch: Bool {
        switch self {
        case .singleVideo: return false
        case .playlist, .channel: return true
        }
    }
    
    public var targetURL: String {
        switch self {
        case .singleVideo(let video): return video.canonicalURL
        case .playlist(let url, _, _): return url
        case .channel(let url, _): return url
        }
    }
}

public enum URLParser {
    private static let validHosts: Set<String> = [
        "youtube.com",
        "www.youtube.com",
        "m.youtube.com",
        "music.youtube.com",
        "youtu.be",
        "www.youtube-nocookie.com"
    ]
    
    private static let validIDCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
    
    /// Detects whether a URL represents a single video, a playlist, or an entire channel.
    public static func detectType(_ urlString: String) -> YouTubeLinkType? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: withScheme),
              let host = components.host?.lowercased(),
              validHosts.contains(host) else {
            return nil
        }
        
        let path = components.path
        
        // 1. Channel URL patterns:
        // /@handle (e.g. /@mkbhd or /@mkbhd/videos)
        if path.hasPrefix("/@") {
            let withoutLeadingSlash = String(path.dropFirst())
            let handle = withoutLeadingSlash.components(separatedBy: "/").first ?? withoutLeadingSlash
            guard !handle.isEmpty else { return nil }
            let canonical = "https://www.youtube.com/\(handle)/videos"
            return .channel(url: canonical, channelIdentifier: handle)
        }
        
        // /channel/UC...
        if path.hasPrefix("/channel/") {
            let identifier = String(path.dropFirst("/channel/".count)).components(separatedBy: "/").first ?? ""
            guard !identifier.isEmpty else { return nil }
            let canonical = "https://www.youtube.com/channel/\(identifier)/videos"
            return .channel(url: canonical, channelIdentifier: identifier)
        }
        
        // /c/CustomName
        if path.hasPrefix("/c/") {
            let identifier = String(path.dropFirst("/c/".count)).components(separatedBy: "/").first ?? ""
            guard !identifier.isEmpty else { return nil }
            let canonical = "https://www.youtube.com/c/\(identifier)/videos"
            return .channel(url: canonical, channelIdentifier: identifier)
        }
        
        // /user/UserName
        if path.hasPrefix("/user/") {
            let identifier = String(path.dropFirst("/user/".count)).components(separatedBy: "/").first ?? ""
            guard !identifier.isEmpty else { return nil }
            let canonical = "https://www.youtube.com/user/\(identifier)/videos"
            return .channel(url: canonical, channelIdentifier: identifier)
        }
        
        // 2. Pure playlist URL: /playlist?list=...
        if path == "/playlist" {
            if let listID = components.queryItems?.first(where: { $0.name == "list" })?.value,
               !listID.isEmpty {
                return .playlist(url: "https://www.youtube.com/playlist?list=\(listID)", playlistID: listID, videoID: nil)
            }
            return nil
        }
        
        // 3. Watch or youtu.be URL that also contains a playlist param &list=...
        let queryListID = components.queryItems?.first(where: { $0.name == "list" })?.value
        let singleParsed = parseSingle(withScheme)
        
        if let listID = queryListID, !listID.isEmpty {
            return .playlist(
                url: "https://www.youtube.com/playlist?list=\(listID)",
                playlistID: listID,
                videoID: singleParsed?.videoID
            )
        }
        
        // 4. Regular single video
        if let single = singleParsed {
            return .singleVideo(single)
        }
        
        return nil
    }
    
    /// Parses a single URL string and returns ParsedYouTubeVideo if valid.
    public static func parseSingle(_ urlString: String) -> ParsedYouTubeVideo? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let host = components.host?.lowercased(),
              validHosts.contains(host) else {
            return nil
        }
        
        var candidateID: String? = nil
        
        if host == "youtu.be" {
            let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            candidateID = path
        } else {
            let path = components.path
            if path == "/watch" {
                candidateID = components.queryItems?.first(where: { $0.name == "v" })?.value
            } else if path.hasPrefix("/shorts/") {
                candidateID = String(path.dropFirst("/shorts/".count))
            } else if path.hasPrefix("/live/") {
                candidateID = String(path.dropFirst("/live/".count))
            } else if path.hasPrefix("/embed/") {
                candidateID = String(path.dropFirst("/embed/".count))
            }
        }
        
        guard let id = candidateID, isValidID(id) else {
            return nil
        }
        
        return ParsedYouTubeVideo(videoID: id)
    }
    
    /// Extracts all valid YouTube video references from a multi-line or bulk pasted string.
    public static func parseBulk(_ text: String) -> [ParsedYouTubeVideo] {
        var results: [ParsedYouTubeVideo] = []
        var seenIDs = Set<String>()
        
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)) ?? []
        
        for match in matches {
            guard let url = match.url else { continue }
            if let parsed = parseSingle(url.absoluteString), !seenIDs.contains(parsed.videoID) {
                seenIDs.insert(parsed.videoID)
                results.append(parsed)
            }
        }
        
        // Also split by tokens in case URLs don't have http/https prefix
        let tokens = text.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        for token in tokens where !token.isEmpty {
            let withScheme = token.contains("://") ? token : "https://\(token)"
            if let parsed = parseSingle(withScheme), !seenIDs.contains(parsed.videoID) {
                seenIDs.insert(parsed.videoID)
                results.append(parsed)
            }
        }
        
        return results
    }
    
    public static func isValidID(_ id: String) -> Bool {
        guard id.count == 11 else { return false }
        return id.unicodeScalars.allSatisfy { validIDCharacters.contains($0) }
    }
}
