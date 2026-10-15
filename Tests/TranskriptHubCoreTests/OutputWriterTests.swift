import Foundation
import Testing
@testable import TranskriptHubCore

@Test func testOutputWriterFilenameSanitization() throws {
    let rawTitle = "YouTube: FDE / AI & DevOps? [Training] * <Important> | Test"
    let sanitized = OutputWriter.sanitizeFilename(rawTitle)
    
    #expect(!sanitized.contains(":"))
    #expect(!sanitized.contains("/"))
    #expect(!sanitized.contains("?"))
    #expect(!sanitized.contains("*"))
    #expect(!sanitized.contains("<"))
    #expect(!sanitized.contains(">"))
    #expect(!sanitized.contains("|"))
    #expect(!sanitized.contains("  "))
    #expect(sanitized.count <= 150)
}

@Test func testOutputWriterCollisionResolution() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    
    let writer = OutputWriter(customOutputDirectory: tempDir)
    
    // File 1
    let url1 = writer.resolveUniqueURL(forBaseName: "Sample", in: tempDir)
    #expect(url1.lastPathComponent == "Sample.txt")
    try writer.write(content: "First file", to: url1)
    
    // File 2 (conflict)
    let url2 = writer.resolveUniqueURL(forBaseName: "Sample", in: tempDir)
    #expect(url2.lastPathComponent == "Sample (2).txt")
    try writer.write(content: "Second file", to: url2)
    
    // File 3 (conflict)
    let url3 = writer.resolveUniqueURL(forBaseName: "Sample", in: tempDir)
    #expect(url3.lastPathComponent == "Sample (3).txt")
    try writer.write(content: "Third file", to: url3)
    
    // Verify file contents
    let content1 = try String(contentsOf: url1, encoding: .utf8)
    let content2 = try String(contentsOf: url2, encoding: .utf8)
    #expect(content1 == "First file")
    #expect(content2 == "Second file")
}
