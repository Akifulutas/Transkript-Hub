import Foundation
import Testing
@testable import TranskriptHubCore

@Test func testOutputWriterFilenameSanitization() throws {
    let rawTitle = "YouTube: FDE / AI & DevOps? [Eğitim] * <Önemli> | Test"
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
    let url1 = writer.resolveUniqueURL(forBaseName: "Deneme", in: tempDir)
    #expect(url1.lastPathComponent == "Deneme.txt")
    try writer.write(content: "İlk dosya", to: url1)
    
    // File 2 (conflict)
    let url2 = writer.resolveUniqueURL(forBaseName: "Deneme", in: tempDir)
    #expect(url2.lastPathComponent == "Deneme (2).txt")
    try writer.write(content: "İkinci dosya", to: url2)
    
    // File 3 (conflict)
    let url3 = writer.resolveUniqueURL(forBaseName: "Deneme", in: tempDir)
    #expect(url3.lastPathComponent == "Deneme (3).txt")
    try writer.write(content: "Üçüncü dosya", to: url3)
    
    // Verify file contents
    let content1 = try String(contentsOf: url1, encoding: .utf8)
    let content2 = try String(contentsOf: url2, encoding: .utf8)
    #expect(content1 == "İlk dosya")
    #expect(content2 == "İkinci dosya")
}
