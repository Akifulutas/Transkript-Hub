import Foundation
import Testing
@testable import TranskriptHubCore

@Test func testAudioValidatorExtensionFiltering() throws {
    #expect(AudioValidator.isExtensionSupported("m4a"))
    #expect(AudioValidator.isExtensionSupported("mp3"))
    #expect(AudioValidator.isExtensionSupported("wav"))
    #expect(AudioValidator.isExtensionSupported("aac"))
    #expect(AudioValidator.isExtensionSupported("caf"))
    
    #expect(!AudioValidator.isExtensionSupported("txt"))
    #expect(!AudioValidator.isExtensionSupported("pdf"))
    #expect(!AudioValidator.isExtensionSupported("part"))
    #expect(!AudioValidator.isExtensionSupported("download"))
}

@Test func testAudioValidatorOnSampleFile() throws {
    let sampleURL = URL(fileURLWithPath: "Tests/Fixtures/sample.m4a")
    if FileManager.default.fileExists(atPath: sampleURL.path) {
        let duration = try AudioValidator.validate(fileURL: sampleURL)
        #expect(duration > 1.0)
    }
}
