import Foundation
import Testing
import AVFoundation
@testable import TranskriptHubCore

@Suite("Ses Doğrulayıcı (AudioValidator) Derinlik Test Paketi")
struct AudioValidatorDeepTests {
    
    @Test("Desteklenen ve desteklenmeyen uzantıların doğrulanması")
    func testExtensionSupportMatrix() {
        let supported = ["m4a", "M4A", "mp3", "MP3", "wav", "WAV", "aac", "caf", "aiff", "mp4", "mov"]
        for ext in supported {
            #expect(AudioValidator.isExtensionSupported(ext), "Desteklenmeliydi: \(ext)")
        }
        
        let unsupported = ["txt", "pdf", "exe", "dmg", "zip", "flac-unsupported", "sqlite", "sh"]
        for ext in unsupported {
            #expect(!AudioValidator.isExtensionSupported(ext), "Desteklenmemeliydi: \(ext)")
        }
    }
    
    @Test("Olmayan dosya verildiğinde fileNotFound hatası fırlatma")
    func testNonExistentFile() {
        let fakeURL = URL(fileURLWithPath: "/tmp/non_existent_audio_\(UUID().uuidString).m4a")
        #expect(throws: AudioValidationError.self) {
            try AudioValidator.validate(fileURL: fakeURL)
        }
    }
    
    @Test("0 baytlık boş dosya verildiğinde emptyFile hatası fırlatma")
    func testZeroByteFile() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("empty_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: tempURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        #expect(throws: AudioValidationError.self) {
            try AudioValidator.validate(fileURL: tempURL)
        }
    }
    
    @Test("Ses formatında olmayan sahte metin dosyası verildiğinde unreadable hatası")
    func testFakeAudioFile() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("fake_\(UUID().uuidString).wav")
        let dummyData = "Bu aslında bir metin dosyasıdır, ses dosyası değildir.".data(using: .utf8)!
        try dummyData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        #expect(throws: AudioValidationError.self) {
            try AudioValidator.validate(fileURL: tempURL)
        }
    }
    
    @Test("Geçerli ses örneğinin başarıyla doğrulanması ve süre hesaplaması")
    func testValidAudioSample() throws {
        let sampleURL = URL(fileURLWithPath: "Tests/Fixtures/sample.m4a")
        guard FileManager.default.fileExists(atPath: sampleURL.path) else { return }
        
        let duration = try AudioValidator.validate(fileURL: sampleURL)
        #expect(duration > 1.0, "Örnek ses süresi 1 saniyeden uzun olmalıydı")
    }
}
