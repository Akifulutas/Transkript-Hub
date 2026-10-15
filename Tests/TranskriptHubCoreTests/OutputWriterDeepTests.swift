import Foundation
import Testing
@testable import TranskriptHubCore

@Suite("OutputWriter Comprehensive Test Suite")
struct OutputWriterDeepTests {
    
    @Test("Filename sanitization and special character cleansing")
    func testFilenameSanitizationEdgeCases() {
        let dirtyTitles: [(input: String, expected: String)] = [
            ("Video/Title:Sub\\Title*?\"<>|", "Video-Title-Sub-Title"),
            ("   ...Leading and Trailing Dots...   ", "Leading and Trailing Dots"),
            ("Wide    Multiple     Spaces", "Wide Multiple Spaces"),
            ("A---B----C", "A-B-C"),
            ("", "Transkript"),
            ("...", "Transkript"),
            ("Unicode Characters: éöàç ĞÜŞİÖÇ", "Unicode Characters- éöàç ĞÜŞİÖÇ")
        ]
        
        for item in dirtyTitles {
            let sanitized = OutputWriter.sanitizeFilename(item.input)
            #expect(sanitized == item.expected, "Expected: '\(item.expected)', Received: '\(sanitized)'")
            #expect(!sanitized.contains("/"))
            #expect(!sanitized.contains(":"))
            #expect(!sanitized.contains("\\"))
            #expect(!sanitized.contains("*"))
            #expect(!sanitized.contains("?"))
            #expect(!sanitized.contains("\""))
            #expect(!sanitized.contains("<"))
            #expect(!sanitized.contains(">"))
            #expect(!sanitized.contains("|"))
        }
    }
    
    @Test("Safe truncation of filenames longer than 150 characters")
    func testLongFilenameTruncation() {
        let longTitle = String(repeating: "LongTitleWord-", count: 20) // ~300 chars
        let sanitized = OutputWriter.sanitizeFilename(longTitle)
        #expect(sanitized.count <= 150)
        #expect(!sanitized.hasSuffix("-"))
        #expect(!sanitized.hasSuffix("."))
    }
    
    @Test("Sequential collision numbering (2), (3)")
    func testCollisionResolutionSequential() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let writer = OutputWriter(customOutputDirectory: tempDir)
        try writer.ensureDirectoryExists(at: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let baseName = "Podcast_Episode_1"
        
        // 1. file: Podcast_Episode_1.txt
        let url1 = writer.resolveUniqueURL(forBaseName: baseName, in: tempDir)
        #expect(url1.lastPathComponent == "Podcast_Episode_1.txt")
        try writer.write(content: "Content 1", to: url1)
        
        // 2. file: Podcast_Episode_1 (2).txt
        let url2 = writer.resolveUniqueURL(forBaseName: baseName, in: tempDir)
        #expect(url2.lastPathComponent == "Podcast_Episode_1 (2).txt")
        try writer.write(content: "Content 2", to: url2)
        
        // 3. file: Podcast_Episode_1 (3).txt
        let url3 = writer.resolveUniqueURL(forBaseName: baseName, in: tempDir)
        #expect(url3.lastPathComponent == "Podcast_Episode_1 (3).txt")
        try writer.write(content: "Content 3", to: url3)
    }
    
    @Test("Atomic write guarantee and verification")
    func testAtomicWriteIntegrity() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let writer = OutputWriter(customOutputDirectory: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let targetURL = tempDir.appendingPathComponent("Atomic_Test.txt")
        let testContent = "This is critical transcript content written atomically."
        
        try writer.write(content: testContent, to: targetURL)
        
        // Primary file must exist
        #expect(FileManager.default.fileExists(atPath: targetURL.path))
        
        // Temporary partial file must not remain
        let partialURL = tempDir.appendingPathComponent(".Atomic_Test.txt.partial")
        #expect(!FileManager.default.fileExists(atPath: partialURL.path))
        
        // Content must match verbatim
        let readBack = try String(contentsOf: targetURL, encoding: .utf8)
        #expect(readBack == testContent)
    }
}
