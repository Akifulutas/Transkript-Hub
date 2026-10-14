import Foundation
import Testing
@testable import TranskriptHubCore

@Suite("Çıktı Yazıcı (OutputWriter) Kapsamlı Test Paketi")
struct OutputWriterDeepTests {
    
    @Test("Dosya adı temizleme ve geçersiz karakterlerin ayıklanması")
    func testFilenameSanitizationEdgeCases() {
        let dirtyTitles: [(input: String, expected: String)] = [
            ("Video/Başlık:Alt\\Başlık*?\"<>|", "Video-Başlık-Alt-Başlık"),
            ("   ...Başında ve Sonunda Noktalar...   ", "Başında ve Sonunda Noktalar"),
            ("Çok    Geniş     Boşluklar", "Çok Geniş Boşluklar"),
            ("A---B----C", "A-B-C"),
            ("", "Transkript"),
            ("...", "Transkript"),
            ("Türkçe Karakterler: ğüşıöç ĞÜŞİÖÇ", "Türkçe Karakterler- ğüşıöç ĞÜŞİÖÇ")
        ]
        
        for item in dirtyTitles {
            let sanitized = OutputWriter.sanitizeFilename(item.input)
            #expect(sanitized == item.expected, "Beklenen: '\(item.expected)', Alınan: '\(sanitized)'")
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
    
    @Test("150 karakterden uzun başlıkların güvenle kırpılması")
    func testLongFilenameTruncation() {
        let longTitle = String(repeating: "UzunBaşlıkKelimesi-", count: 20) // ~400 karakter
        let sanitized = OutputWriter.sanitizeFilename(longTitle)
        #expect(sanitized.count <= 150)
        #expect(!sanitized.hasSuffix("-"))
        #expect(!sanitized.hasSuffix("."))
    }
    
    @Test("Dosya çakışmalarında otomatik artan numara (2), (3) verilmesi")
    func testCollisionResolutionSequential() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let writer = OutputWriter(customOutputDirectory: tempDir)
        try writer.ensureDirectoryExists(at: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let baseName = "Podcast_Bolum_1"
        
        // 1. dosya: Podcast_Bolum_1.txt
        let url1 = writer.resolveUniqueURL(forBaseName: baseName, in: tempDir)
        #expect(url1.lastPathComponent == "Podcast_Bolum_1.txt")
        try writer.write(content: "İçerik 1", to: url1)
        
        // 2. dosya: Podcast_Bolum_1 (2).txt
        let url2 = writer.resolveUniqueURL(forBaseName: baseName, in: tempDir)
        #expect(url2.lastPathComponent == "Podcast_Bolum_1 (2).txt")
        try writer.write(content: "İçerik 2", to: url2)
        
        // 3. dosya: Podcast_Bolum_1 (3).txt
        let url3 = writer.resolveUniqueURL(forBaseName: baseName, in: tempDir)
        #expect(url3.lastPathComponent == "Podcast_Bolum_1 (3).txt")
        try writer.write(content: "İçerik 3", to: url3)
    }
    
    @Test("Atomik yazma ve doğrulama garantisi")
    func testAtomicWriteIntegrity() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let writer = OutputWriter(customOutputDirectory: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let targetURL = tempDir.appendingPathComponent("Atomik_Test.txt")
        let testContent = "Bu atomik olarak yazılmış kritik bir transkript metnidir."
        
        try writer.write(content: testContent, to: targetURL)
        
        // Asıl dosya var olmalı
        #expect(FileManager.default.fileExists(atPath: targetURL.path))
        
        // Geçici kısmi dosya kalmamış olmalı
        let partialURL = tempDir.appendingPathComponent(".Atomik_Test.txt.partial")
        #expect(!FileManager.default.fileExists(atPath: partialURL.path))
        
        // İçerik birebir eşleşmeli
        let readBack = try String(contentsOf: targetURL, encoding: .utf8)
        #expect(readBack == testContent)
    }
}
