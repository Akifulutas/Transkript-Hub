import Foundation

public struct YouTubeVideoInfo: Sendable, Codable {
    public let videoID: String
    public let title: String
    public let authorName: String?
    public let authorURL: String?
    public let thumbnailURL: URL?
    
    public init(videoID: String, title: String, authorName: String?, authorURL: String?, thumbnailURL: URL?) {
        self.videoID = videoID
        self.title = title
        self.authorName = authorName
        self.authorURL = authorURL
        self.thumbnailURL = thumbnailURL
    }
}

public actor YouTubeMetadataResolver {
    public static let shared = YouTubeMetadataResolver()
    
    private var cache: [String: YouTubeVideoInfo] = [:]
    
    private struct OEmbedResponse: Codable {
        let title: String?
        let author_name: String?
        let author_url: String?
        let thumbnail_url: String?
    }
    
    public init() {}
    
    public func cachedInfo(for videoID: String) -> YouTubeVideoInfo? {
        cache[videoID]
    }
    
    public func resolve(videoID: String) async -> YouTubeVideoInfo {
        if let cached = cache[videoID] {
            return cached
        }
        
        // Default deterministic thumbnail URL
        let fallbackThumb = URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
        
        let urlString = "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(videoID)&format=json"
        guard let url = URL(string: urlString) else {
            let fallback = YouTubeVideoInfo(
                videoID: videoID,
                title: "YouTube Videosu (\(videoID))",
                authorName: "YouTube",
                authorURL: nil,
                thumbnailURL: fallbackThumb
            )
            cache[videoID] = fallback
            return fallback
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 3.5
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                let decoded = try JSONDecoder().decode(OEmbedResponse.self, from: data)
                if let rawTitle = decoded.title, !rawTitle.isEmpty {
                    // Clean HTML entities if any (e.g. &#39; -> ', &amp; -> &)
                    let cleanTitle = cleanHTMLEntities(rawTitle)
                    let cleanAuthor = decoded.author_name.map { cleanHTMLEntities($0) }
                    let thumb = decoded.thumbnail_url.flatMap { URL(string: $0) } ?? fallbackThumb
                    
                    let info = YouTubeVideoInfo(
                        videoID: videoID,
                        title: cleanTitle,
                        authorName: cleanAuthor ?? "YouTube",
                        authorURL: decoded.author_url,
                        thumbnailURL: thumb
                    )
                    cache[videoID] = info
                    return info
                }
            }
        } catch {
            // Silently fall back to deterministic info
        }
        
        let fallback = YouTubeVideoInfo(
            videoID: videoID,
            title: "YouTube Videosu (\(videoID))",
            authorName: "YouTube",
            authorURL: nil,
            thumbnailURL: fallbackThumb
        )
        cache[videoID] = fallback
        return fallback
    }
    
    private func cleanHTMLEntities(_ string: String) -> String {
        var result = string
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        return result
    }
}
