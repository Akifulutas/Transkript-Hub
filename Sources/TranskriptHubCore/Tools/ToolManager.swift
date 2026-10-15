import Foundation

public enum ToolManagerError: Error, LocalizedError {
    case downloadFailed(String)
    case extractionFailed(String)
    case executionPermissionFailed(String)
    case toolNotFound(String)
    
    public var errorDescription: String? {
        switch self {
        case .downloadFailed(let msg):
            return "Araç indirme hatası: \(msg)"
        case .extractionFailed(let msg):
            return "Araç arşivden çıkarılamadı: \(msg)"
        case .executionPermissionFailed(let msg):
            return "Çalıştırma izni verilemedi: \(msg)"
        case .toolNotFound(let msg):
            return "Gerekli araç bulunamadı: \(msg)"
        }
    }
}

public final class ToolManager: Sendable {
    public let toolsDirectory: URL
    
    public init(toolsDirectory: URL? = nil) {
        if let dir = toolsDirectory {
            self.toolsDirectory = dir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.toolsDirectory = appSupport.appendingPathComponent("TranskriptHub/Tools", isDirectory: true)
        }
    }
    
    public var ytdlpExecutableURL: URL {
        toolsDirectory.appendingPathComponent("yt-dlp/current/yt-dlp")
    }
    
    public var denoExecutableURL: URL {
        toolsDirectory.appendingPathComponent("deno/current/deno")
    }
    
    public func isYTDLPReady() -> Bool {
        let path = ytdlpExecutableURL.path
        return FileManager.default.isExecutableFile(atPath: path)
    }
    
    public func isDenoReady() -> Bool {
        let path = denoExecutableURL.path
        return FileManager.default.isExecutableFile(atPath: path)
    }
    
    public func ensureToolsReady(progress: (@Sendable (String, Double) -> Void)? = nil) async throws {
        try ensureDirectoryExists()
        
        if !isYTDLPReady() {
            try await installYTDLP(progress: { ratio in
                progress?("yt-dlp indiriliyor", ratio)
            })
        } else {
            progress?("yt-dlp hazır", 1.0)
        }
        
        if !isDenoReady() {
            try await installDeno(progress: { ratio in
                progress?("deno indiriliyor", ratio)
            })
        } else {
            progress?("deno hazır", 1.0)
        }
    }
    
    private func ensureDirectoryExists() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: toolsDirectory.path) {
            try fm.createDirectory(at: toolsDirectory, withIntermediateDirectories: true)
        }
    }
    
    public func installYTDLP(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        Log.info("Installing yt-dlp...")
        let ytdlpDir = toolsDirectory.appendingPathComponent("yt-dlp", isDirectory: true)
        let currentDir = ytdlpDir.appendingPathComponent("current", isDirectory: true)
        try FileManager.default.createDirectory(at: currentDir, withIntermediateDirectories: true)
        
        let destination = currentDir.appendingPathComponent("yt-dlp")
        let downloadURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
        
        let (tempURL, response) = try await URLSession.shared.download(from: downloadURL)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw ToolManagerError.downloadFailed("Failed to download yt-dlp (HTTP error).")
        }
        
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: tempURL, to: destination)
        
        // chmod +x
        try makeExecutable(at: destination)
        removeQuarantine(at: destination)
        
        Log.info("yt-dlp successfully installed: \(destination.path)")
        progress?(1.0)
    }
    
    public func installDeno(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        Log.info("Installing Deno...")
        let denoDir = toolsDirectory.appendingPathComponent("deno", isDirectory: true)
        let currentDir = denoDir.appendingPathComponent("current", isDirectory: true)
        try FileManager.default.createDirectory(at: currentDir, withIntermediateDirectories: true)
        
        let destination = currentDir.appendingPathComponent("deno")
        let downloadURL = URL(string: "https://github.com/denoland/deno/releases/latest/download/deno-aarch64-apple-darwin.zip")!
        
        let (tempZipURL, response) = try await URLSession.shared.download(from: downloadURL)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw ToolManagerError.downloadFailed("Failed to download Deno (HTTP error).")
        }
        
        let tempExtractDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempExtractDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempExtractDir) }
        
        // Unzip deno
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", tempZipURL.path, "-d", tempExtractDir.path]
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw ToolManagerError.extractionFailed("Failed to extract deno.zip.")
        }
        
        let extractedDeno = tempExtractDir.appendingPathComponent("deno")
        guard FileManager.default.fileExists(atPath: extractedDeno.path) else {
            throw ToolManagerError.extractionFailed("Deno binary not found in archive.")
        }
        
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: extractedDeno, to: destination)
        
        // chmod +x
        try makeExecutable(at: destination)
        removeQuarantine(at: destination)
        
        Log.info("Deno successfully installed: \(destination.path)")
        progress?(1.0)
    }
    
    private func makeExecutable(at url: URL) throws {
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber ?? 0
        let newPerms = permissions.intValue | 0o755
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: newPerms)], ofItemAtPath: url.path)
    }
    
    private func removeQuarantine(at url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-d", "com.apple.quarantine", url.path]
        try? process.run()
        process.waitUntilExit()
    }
}
