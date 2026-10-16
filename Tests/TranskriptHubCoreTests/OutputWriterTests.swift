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

@Test func testOutputWriterCustomOutputDirectoryPersistence() throws {
    let key = OutputWriter.customOutputDirectoryDefaultsKey
    let previous = UserDefaults.standard.string(forKey: key)
    defer {
        if let previous {
            UserDefaults.standard.set(previous, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    
    UserDefaults.standard.removeObject(forKey: key)
    let writer = OutputWriter()
    #expect(!writer.isUsingCustomOutputDirectory)
    #expect(writer.defaultOutputDirectory == OutputWriter.systemDefaultOutputDirectory)
    
    let customDir = FileManager.default.temporaryDirectory.appendingPathComponent("CustomTranscriptOutput_\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: customDir) }
    
    writer.setCustomOutputDirectory(customDir)
    #expect(writer.isUsingCustomOutputDirectory)
    #expect(writer.defaultOutputDirectory.path == customDir.path)
    
    let targetURL = writer.resolveUniqueURL(forBaseName: "AutoWatchedSample")
    try writer.write(content: "Auto transcribed text", to: targetURL)
    #expect(targetURL.deletingLastPathComponent().path == customDir.path)
    #expect(FileManager.default.fileExists(atPath: targetURL.path))
    
    writer.setCustomOutputDirectory(nil)
    #expect(!writer.isUsingCustomOutputDirectory)
    #expect(writer.defaultOutputDirectory == OutputWriter.systemDefaultOutputDirectory)
}
