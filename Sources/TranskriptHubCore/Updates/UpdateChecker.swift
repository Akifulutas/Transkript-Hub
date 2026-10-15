import Foundation

public struct AppUpdateInfo: Sendable {
    public let latestVersion: String
    public let releaseNotes: String
    public let htmlURL: String
    public let publishedAt: Date?
    public let isNewerThanCurrent: Bool
    public let checkedAt: Date
    
    public init(
        latestVersion: String,
        releaseNotes: String,
        htmlURL: String,
        publishedAt: Date?,
        isNewerThanCurrent: Bool,
        checkedAt: Date = Date()
    ) {
        self.latestVersion = latestVersion
        self.releaseNotes = releaseNotes
        self.htmlURL = htmlURL
        self.publishedAt = publishedAt
        self.isNewerThanCurrent = isNewerThanCurrent
        self.checkedAt = checkedAt
    }
}

public actor UpdateChecker {
    public static let currentVersion = "1.1.0"
    
    public init() {}
    
    public func checkForUpdates() async throws -> AppUpdateInfo {
        let endpoint = URL(string: "https://api.github.com/repos/Akifulutas/Transkript-Hub/releases/latest")!
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("TranskriptHub-App/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode == 404 {
            // No releases published yet on repository
            return AppUpdateInfo(
                latestVersion: Self.currentVersion,
                releaseNotes: "Şu anda en güncel sürümü (v\(Self.currentVersion)) kullanıyorsunuz.",
                htmlURL: "https://github.com/Akifulutas/Transkript-Hub",
                publishedAt: Date(),
                isNewerThanCurrent: false
            )
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        
        let cleanTag = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let body = (json["body"] as? String) ?? "Hata düzeltmeleri ve kararlılık geliştirmeleri."
        let htmlUrl = (json["html_url"] as? String) ?? "https://github.com/Akifulutas/Transkript-Hub/releases"
        
        let isNewer = isVersion(cleanTag, newerThan: Self.currentVersion)
        
        return AppUpdateInfo(
            latestVersion: cleanTag,
            releaseNotes: body,
            htmlURL: htmlUrl,
            publishedAt: Date(),
            isNewerThanCurrent: isNewer
        )
    }
    
    private func isVersion(_ v1: String, newerThan v2: String) -> Bool {
        let p1 = v1.split(separator: ".").compactMap { Int($0) }
        let p2 = v2.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(p1.count, p2.count) {
            let num1 = i < p1.count ? p1[i] : 0
            let num2 = i < p2.count ? p2[i] : 0
            if num1 > num2 { return true }
            if num1 < num2 { return false }
        }
        return false
    }
}
