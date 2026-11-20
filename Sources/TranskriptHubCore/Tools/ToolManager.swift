import Foundation
import CryptoKit

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

private actor ToolInstallCoordinator {
    static let shared = ToolInstallCoordinator()
    private var inFlightYTDLP: Task<Void, Error>?
    private var inFlightDeno: Task<Void, Error>?
    
    func runYTDLP(_ operation: @Sendable @escaping () async throws -> Void) async throws {
        if let existing = inFlightYTDLP {
            return try await existing.value
        }
        let task = Task {
            try await operation()
        }
        inFlightYTDLP = task
        defer { inFlightYTDLP = nil }
        try await task.value
    }
    
    func runDeno(_ operation: @Sendable @escaping () async throws -> Void) async throws {
        if let existing = inFlightDeno {
            return try await existing.value
        }
        let task = Task {
            try await operation()
        }
        inFlightDeno = task
        defer { inFlightDeno = nil }
        try await task.value
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
    
    public func ensureToolsReady(
        includeDeno: Bool = false,
        progress: (@Sendable (String, Double) -> Void)? = nil
    ) async throws {
        try ensureDirectoryExists()
        
        if !isYTDLPReady() {
            try await installYTDLP(progress: { ratio in
                progress?("yt-dlp indiriliyor", ratio)
            })
        } else {
            progress?("yt-dlp hazır", 1.0)
        }
        
        if includeDeno {
            if !isDenoReady() {
                try await installDeno(progress: { ratio in
                    progress?("deno indiriliyor", ratio)
                })
            } else {
                progress?("deno hazır", 1.0)
            }
        }
    }
    
    private func ensureDirectoryExists() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: toolsDirectory.path) {
            try fm.createDirectory(at: toolsDirectory, withIntermediateDirectories: true)
        }
    }
    
    public func installYTDLP(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        try await ToolInstallCoordinator.shared.runYTDLP {
            if self.isYTDLPReady() {
                progress?(1.0)
                return
            }
            Log.info("Installing yt-dlp...")
            let ytdlpDir = self.toolsDirectory.appendingPathComponent("yt-dlp", isDirectory: true)
            let currentDir = ytdlpDir.appendingPathComponent("current", isDirectory: true)
            try FileManager.default.createDirectory(at: currentDir, withIntermediateDirectories: true)
            
            let destination = currentDir.appendingPathComponent("yt-dlp")
            let downloadURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
            let checksumsURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS")!
            
            let (tempURL, response) = try await URLSession.shared.download(from: downloadURL)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw ToolManagerError.downloadFailed("Failed to download yt-dlp (HTTP error).")
            }
            
            let stagedURL = currentDir.appendingPathComponent("yt-dlp.staging.\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: stagedURL) }
            try FileManager.default.moveItem(at: tempURL, to: stagedURL)
            
            try await self.verifyBinaryIntegrity(
                fileURL: stagedURL,
                assetFilename: "yt-dlp_macos",
                checksumsURL: checksumsURL
            )
            
            try self.makeExecutable(at: stagedURL)
            self.removeQuarantine(at: stagedURL)
            try self.atomicReplace(at: destination, with: stagedURL)
            
            Log.info("yt-dlp successfully installed: \(destination.path)")
            progress?(1.0)
        }
    }
    
    public func installDeno(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        try await ToolInstallCoordinator.shared.runDeno {
            if self.isDenoReady() {
                progress?(1.0)
                return
            }
            Log.info("Installing Deno...")
            let denoDir = self.toolsDirectory.appendingPathComponent("deno", isDirectory: true)
            let currentDir = denoDir.appendingPathComponent("current", isDirectory: true)
            try FileManager.default.createDirectory(at: currentDir, withIntermediateDirectories: true)
            
            let destination = currentDir.appendingPathComponent("deno")
            let archString: String
            #if arch(arm64)
            archString = "aarch64"
            #else
            archString = "x86_64"
            #endif
            let archiveName = "deno-\(archString)-apple-darwin.zip"
            let downloadURL = URL(string: "https://github.com/denoland/deno/releases/latest/download/\(archiveName)")!
            let checksumsURL = URL(string: "https://github.com/denoland/deno/releases/latest/download/\(archiveName).sha256sum")!
            
            let (tempZipURL, response) = try await URLSession.shared.download(from: downloadURL)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw ToolManagerError.downloadFailed("Failed to download Deno (HTTP error).")
            }
            
            try await self.verifyBinaryIntegrity(
                fileURL: tempZipURL,
                assetFilename: archiveName,
                checksumsURL: checksumsURL
            )
            
            let tempExtractDir = FileManager.default.temporaryDirectory.appendingPathComponent("deno_extract_\(UUID().uuidString)", isDirectory: true)
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
            
            let stagedURL = currentDir.appendingPathComponent("deno.staging.\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: stagedURL) }
            try FileManager.default.moveItem(at: extractedDeno, to: stagedURL)
            
            try self.makeExecutable(at: stagedURL)
            self.removeQuarantine(at: stagedURL)
            try self.atomicReplace(at: destination, with: stagedURL)
            
            Log.info("Deno successfully installed: \(destination.path)")
            progress?(1.0)
        }
    }
    
    private func atomicReplace(at destination: URL, with stagedURL: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: stagedURL)
        } else {
            try fm.moveItem(at: stagedURL, to: destination)
        }
    }
    
    /// Verifies that `fileURL` is non-empty and, when the upstream SHA-256 manifest is reachable,
    /// validates the cryptographic SHA-256 digest before Gatekeeper quarantine is stripped.
    private func verifyBinaryIntegrity(
        fileURL: URL,
        assetFilename: String,
        checksumsURL: URL
    ) async throws {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard data.count > 1024 else {
            throw ToolManagerError.downloadFailed("\(assetFilename) downloaded payload is truncated (\(data.count) bytes).")
        }
        
        let actualHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().lowercased()
        
        if let (sumData, response) = try? await URLSession.shared.data(from: checksumsURL),
           let httpResp = response as? HTTPURLResponse,
           (200...299).contains(httpResp.statusCode),
           let sumText = String(data: sumData, encoding: .utf8) {
            for line in sumText.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
                if parts.count >= 2 {
                    let candidateHash = String(parts[0]).lowercased()
                    let candidateFile = String(parts.last!).trimmingCharacters(in: CharacterSet(charactersIn: "*./"))
                    if candidateFile == assetFilename && candidateHash.count == 64 {
                        guard candidateHash == actualHash else {
                            throw ToolManagerError.downloadFailed(
                                "SHA-256 integrity mismatch for \(assetFilename) (expected \(candidateHash), got \(actualHash))."
                            )
                        }
                        Log.info("Verified SHA-256 checksum for \(assetFilename): \(actualHash)")
                        return
                    }
                }
            }
        }
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
