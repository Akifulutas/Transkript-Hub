import Foundation

public enum OutputWriterError: Error, LocalizedError {
    case directoryCreationFailed(String)
    case writeFailed(String)
    case verificationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let msg):
            return "Çıktı klasörü oluşturulamadı: \(msg)"
        case .writeFailed(let msg):
            return "Çıktı dosyası yazılamadı: \(msg)"
        case .verificationFailed(let msg):
            return "Yazılan çıktı dosyası doğrulanamadı: \(msg)"
        }
    }
}

public final class OutputWriter: Sendable {
    public let defaultOutputDirectory: URL
    
    public init(customOutputDirectory: URL? = nil) {
        if let dir = customOutputDirectory {
            self.defaultOutputDirectory = dir
        } else {
            let fileManager = FileManager.default
            let home = fileManager.homeDirectoryForCurrentUser
            let iCloudTranskript = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Transkript", isDirectory: true)
            
            // If iCloud Drive Transkript exists or can be created, use it; otherwise fallback to ~/Documents/Transkript
            let fallbackDocuments = home.appendingPathComponent("Documents/Transkript", isDirectory: true)
            if fileManager.fileExists(atPath: iCloudTranskript.path) {
                self.defaultOutputDirectory = iCloudTranskript
            } else if fileManager.fileExists(atPath: home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs").path) {
                // iCloud Drive is available, we can create Transkript inside
                self.defaultOutputDirectory = iCloudTranskript
            } else {
                self.defaultOutputDirectory = fallbackDocuments
            }
        }
    }
    
    public func ensureDirectoryExists(at directory: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            do {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw OutputWriterError.directoryCreationFailed(error.localizedDescription)
            }
        }
    }
    
    /// Sanitizes file name: replaces illegal characters (/ : \ * ? " < > |) with "-", trims, limits to 150 chars.
    public static func sanitizeFilename(_ name: String) -> String {
        let illegalCharacters = CharacterSet(charactersIn: "/:\\*?\"<>|")
        var sanitized = name.components(separatedBy: illegalCharacters).joined(separator: "-")
        
        // Remove control characters
        sanitized = sanitized.components(separatedBy: .controlCharacters).joined(separator: "")
        
        // Collapse consecutive spaces and hyphens
        while sanitized.contains("  ") {
            sanitized = sanitized.replacingOccurrences(of: "  ", with: " ")
        }
        while sanitized.contains("--") {
            sanitized = sanitized.replacingOccurrences(of: "--", with: "-")
        }
        
        // Trim whitespace and dots
        sanitized = sanitized.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        
        // Max 150 characters
        if sanitized.count > 150 {
            sanitized = String(sanitized.prefix(150)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        if sanitized.isEmpty {
            sanitized = "Transkript"
        }
        
        return sanitized
    }
    
    /// Resolves file collision: if 'Name.txt' exists, returns 'Name (2).txt', etc.
    public func resolveUniqueURL(forBaseName baseName: String, in directory: URL) -> URL {
        let sanitized = Self.sanitizeFilename(baseName)
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent("\(sanitized).txt")
        
        if !fm.fileExists(atPath: candidate.path) {
            return candidate
        }
        
        var counter = 2
        while true {
            candidate = directory.appendingPathComponent("\(sanitized) (\(counter)).txt")
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
    
    /// Atomically writes text content to destination: writes to .<filename>.partial, verifies, and renames.
    public func write(content: String, to destinationURL: URL) throws {
        let directory = destinationURL.deletingLastPathComponent()
        try ensureDirectoryExists(at: directory)
        
        let filename = destinationURL.lastPathComponent
        let partialURL = directory.appendingPathComponent(".\(filename).partial")
        
        let fm = FileManager.default
        // Remove old partial if exists
        if fm.fileExists(atPath: partialURL.path) {
            try? fm.removeItem(at: partialURL)
        }
        
        guard let data = content.data(using: .utf8) else {
            throw OutputWriterError.writeFailed("Metin UTF-8 verisine dönüştürülemedi.")
        }
        
        do {
            try data.write(to: partialURL, options: .atomic)
        } catch {
            throw OutputWriterError.writeFailed(error.localizedDescription)
        }
        
        // Verify written data
        do {
            let readData = try Data(contentsOf: partialURL)
            guard readData.count == data.count else {
                throw OutputWriterError.verificationFailed("Yazılan dosya boyutu kaynak veriyle eşleşmiyor.")
            }
        } catch {
            throw OutputWriterError.verificationFailed(error.localizedDescription)
        }
        
        // Atomic replace/rename
        do {
            if fm.fileExists(atPath: destinationURL.path) {
                _ = try fm.replaceItemAt(destinationURL, withItemAt: partialURL)
            } else {
                try fm.moveItem(at: partialURL, to: destinationURL)
            }
        } catch {
            throw OutputWriterError.writeFailed("Geçici dosya nihai konuma taşınamadı: \(error.localizedDescription)")
        }
    }
}
