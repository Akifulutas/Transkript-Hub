import Foundation

public struct AppUpdateInfo: Sendable {
    public let latestVersion: String
    public let releaseNotes: String
    public let htmlURL: String
    public let downloadURL: String
    public let publishedAt: Date?
    public let isNewerThanCurrent: Bool
    public let checkedAt: Date
    public let latestCommitMessage: String?
    
    public init(
        latestVersion: String,
        releaseNotes: String,
        htmlURL: String,
        downloadURL: String = "https://github.com/Akifulutas/Transkript-Hub/releases/latest/download/TranskriptHub.dmg",
        publishedAt: Date?,
        isNewerThanCurrent: Bool,
        checkedAt: Date = Date(),
        latestCommitMessage: String? = nil
    ) {
        self.latestVersion = latestVersion
        self.releaseNotes = releaseNotes
        self.htmlURL = htmlURL
        self.downloadURL = downloadURL
        self.publishedAt = publishedAt
        self.isNewerThanCurrent = isNewerThanCurrent
        self.checkedAt = checkedAt
        self.latestCommitMessage = latestCommitMessage
    }
}

public actor UpdateChecker {
    public static let currentVersion = "1.4.0"
    public static let defaultDMGDownloadURL = "https://github.com/Akifulutas/Transkript-Hub/releases/latest/download/TranskriptHub.dmg"
    
    public init() {}
    
    public func checkForUpdates() async throws -> AppUpdateInfo {
        do {
            return try await checkViaGitHubAPI()
        } catch {
            return try await checkViaRedirectFallback()
        }
    }
    
    private func checkViaGitHubAPI() async throws -> AppUpdateInfo {
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
            // Check latest commit if no published releases yet
            let commitEndpoint = URL(string: "https://api.github.com/repos/Akifulutas/Transkript-Hub/commits?per_page=1")!
            var commitReq = URLRequest(url: commitEndpoint)
            commitReq.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            commitReq.setValue("TranskriptHub-App/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
            commitReq.timeoutInterval = 5.0
            
            var commitNote = "Şu anda en güncel sürümü (v\(Self.currentVersion)) kullanıyorsunuz."
            var commitMsg: String? = nil
            if let (cData, cResp) = try? await URLSession.shared.data(for: commitReq),
               let cHttp = cResp as? HTTPURLResponse, (200...299).contains(cHttp.statusCode),
               let commitArr = (try? JSONSerialization.jsonObject(with: cData)) as? [[String: Any]],
               let firstCommit = commitArr.first,
               let commitObj = firstCommit["commit"] as? [String: Any],
               let msg = commitObj["message"] as? String {
                let firstLine = msg.components(separatedBy: "\n").first ?? msg
                commitNote = "Son GitHub Güncellemesi: \(firstLine)"
                commitMsg = msg
            }
            
            return AppUpdateInfo(
                latestVersion: Self.currentVersion,
                releaseNotes: commitNote,
                htmlURL: "https://github.com/Akifulutas/Transkript-Hub",
                downloadURL: Self.defaultDMGDownloadURL,
                publishedAt: Date(),
                isNewerThanCurrent: false,
                latestCommitMessage: commitMsg
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
        
        var downloadUrl = Self.defaultDMGDownloadURL
        if let assets = json["assets"] as? [[String: Any]],
           let dmgAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
           let browserUrl = dmgAsset["browser_download_url"] as? String {
            downloadUrl = browserUrl
        }
        
        let isNewer = isVersion(cleanTag, newerThan: Self.currentVersion)
        
        return AppUpdateInfo(
            latestVersion: cleanTag,
            releaseNotes: body,
            htmlURL: htmlUrl,
            downloadURL: downloadUrl,
            publishedAt: Date(),
            isNewerThanCurrent: isNewer
        )
    }
    
    private func checkViaRedirectFallback() async throws -> AppUpdateInfo {
        let endpoint = URL(string: "https://github.com/Akifulutas/Transkript-Hub/releases/latest")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "HEAD"
        request.setValue("TranskriptHub-App/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8.0
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              let finalURL = httpResponse.url else {
            throw URLError(.badServerResponse)
        }
        
        let tagString = finalURL.lastPathComponent
        let cleanTag = tagString.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        
        if cleanTag.isEmpty || cleanTag == "latest" {
            return AppUpdateInfo(
                latestVersion: Self.currentVersion,
                releaseNotes: "Şu anda en güncel sürümü (v\(Self.currentVersion)) kullanıyorsunuz.",
                htmlURL: "https://github.com/Akifulutas/Transkript-Hub",
                downloadURL: Self.defaultDMGDownloadURL,
                publishedAt: Date(),
                isNewerThanCurrent: false
            )
        }
        
        let isNewer = isVersion(cleanTag, newerThan: Self.currentVersion)
        let notes = isNewer
            ? "Yeni Transkript Hub v\(cleanTag) sürümü yayınlandı. İndirmek için Güncelle'ye tıklayın."
            : "Şu anda en güncel sürümü (v\(Self.currentVersion)) kullanıyorsunuz."
        
        return AppUpdateInfo(
            latestVersion: cleanTag,
            releaseNotes: notes,
            htmlURL: finalURL.absoluteString,
            downloadURL: Self.defaultDMGDownloadURL,
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
