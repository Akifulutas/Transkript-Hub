import Foundation
import Testing
import AVFoundation
@testable import TranskriptHubCore

@Suite("Video Audio Extractor & Video Transcription Tests")
struct VideoAudioExtractorTests {
    
    @Test("FFmpeg detector finds executable if installed")
    func testFFmpegDetection() {
        let ffmpeg = VideoAudioExtractor.findFFmpeg()
        if let path = ffmpeg {
            #expect(FileManager.default.isExecutableFile(atPath: path))
        }
    }
    
    @Test("Audio extraction from native MP4 video file")
    func testExtractAudioFromMP4() async throws {
        let testDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_video_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }
        
        let videoURL = testDir.appendingPathComponent("sample_video.mp4")
        
        // If /tmp/test_video.mp4 exists from our earlier generation, copy it; otherwise synthesize a quick test file
        if FileManager.default.fileExists(atPath: "/tmp/test_video.mp4") {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: "/tmp/test_video.mp4"), to: videoURL)
        } else {
            // Generate minimal audio-video via ffmpeg if available
            if let ffmpeg = VideoAudioExtractor.findFFmpeg() {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: ffmpeg)
                process.arguments = ["-y", "-f", "lavfi", "-i", "sine=frequency=1000:duration=1.5", "-f", "lavfi", "-i", "testsrc=duration=1.5:size=320x240:rate=30", "-c:v", "libx264", "-c:a", "aac", videoURL.path]
                try process.run()
                process.waitUntilExit()
            }
        }
        
        guard FileManager.default.fileExists(atPath: videoURL.path) else { return }
        
        let extractor = VideoAudioExtractor.shared
        let extractedAudioURL = try await extractor.extractAudio(from: videoURL, destinationDirectory: testDir)
        
        #expect(FileManager.default.fileExists(atPath: extractedAudioURL.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: extractedAudioURL.path)
        let size = attrs[.size] as? Int64 ?? 0
        #expect(size > 1000)
        
        let duration = try AudioValidator.validate(fileURL: extractedAudioURL)
        #expect(duration >= 1.0)
    }
    
    @Test("Transcript destination resolves strictly next to the source video file")
    func testTranscriptDestinationNextToVideo() throws {
        let videoDir = FileManager.default.temporaryDirectory.appendingPathComponent("MySpecialVideosFolder")
        try FileManager.default.createDirectory(at: videoDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: videoDir) }
        
        let videoFile = videoDir.appendingPathComponent("Conference_Meeting.mp4")
        let baseName = videoFile.deletingPathExtension().lastPathComponent
        let sourceDir = videoFile.deletingLastPathComponent()
        
        let writer = OutputWriter()
        let targetURL = writer.resolveUniqueURL(
            forBaseName: baseName,
            in: sourceDir,
            allowOverwrite: true,
            matchingContent: "Transkript icerigi"
        )
        
        #expect(targetURL.deletingLastPathComponent().path == videoDir.path)
        #expect(targetURL.lastPathComponent == "Conference_Meeting.txt")
        
        try writer.write(content: "Bu bir video transkriptidir.", to: targetURL)
        #expect(FileManager.default.fileExists(atPath: targetURL.path))
        
        let readBack = try String(contentsOf: targetURL, encoding: .utf8)
        #expect(readBack == "Bu bir video transkriptidir.")
    }
}
