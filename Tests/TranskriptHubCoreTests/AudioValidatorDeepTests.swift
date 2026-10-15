import Foundation
import Testing
import AVFoundation
@testable import TranskriptHubCore

@Suite("AudioValidator Comprehensive Test Suite")
struct AudioValidatorDeepTests {
    
    @Test("Validation of supported and unsupported file extensions")
    func testExtensionSupportMatrix() {
        let supported = ["m4a", "M4A", "mp3", "MP3", "wav", "WAV", "aac", "caf", "aiff", "mp4", "mov"]
        for ext in supported {
            #expect(AudioValidator.isExtensionSupported(ext), "Should be supported: \(ext)")
        }
        
        let unsupported = ["txt", "pdf", "exe", "dmg", "zip", "flac-unsupported", "sqlite", "sh"]
        for ext in unsupported {
            #expect(!AudioValidator.isExtensionSupported(ext), "Should not be supported: \(ext)")
        }
    }
    
    @Test("Throwing fileNotFound error for non-existent file")
    func testNonExistentFile() {
        let fakeURL = URL(fileURLWithPath: "/tmp/non_existent_audio_\(UUID().uuidString).m4a")
        #expect(throws: AudioValidationError.self) {
            try AudioValidator.validate(fileURL: fakeURL)
        }
    }
    
    @Test("Throwing emptyFile error for 0-byte file")
    func testZeroByteFile() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("empty_\(UUID().uuidString).m4a")
        FileManager.default.createFile(atPath: tempURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        #expect(throws: AudioValidationError.self) {
            try AudioValidator.validate(fileURL: tempURL)
        }
    }
    
    @Test("Throwing unreadable error for non-audio mock file")
    func testFakeAudioFile() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("fake_\(UUID().uuidString).wav")
        let dummyData = "This is a plain text file, not valid audio data.".data(using: .utf8)!
        try dummyData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        #expect(throws: AudioValidationError.self) {
            try AudioValidator.validate(fileURL: tempURL)
        }
    }
    
    @Test("Successful validation and duration calculation for valid audio sample")
    func testValidAudioSample() throws {
        let sampleURL = URL(fileURLWithPath: "Tests/Fixtures/sample.m4a")
        guard FileManager.default.fileExists(atPath: sampleURL.path) else { return }
        
        let duration = try AudioValidator.validate(fileURL: sampleURL)
        #expect(duration > 1.0, "Sample audio duration should be longer than 1 second")
    }
}
