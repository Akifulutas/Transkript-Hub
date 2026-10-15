import Foundation
import Testing
import AVFoundation
@testable import TranskriptHubCore

@Suite("Audio Player Controller Dedicated Unit Test Suite")
struct AudioPlayerControllerTests {
    
    @Test("Initial state of AudioPlayerController")
    @MainActor
    func testInitialState() {
        let controller = AudioPlayerController()
        
        #expect(controller.currentTime == 0.0)
        #expect(controller.duration == 0.0)
        #expect(controller.isPlaying == false)
        #expect(controller.status == .idle)
        #expect(controller.playbackRate == 1.0)
        #expect(controller.volume == 1.0)
        #expect(controller.isScrubbing == false)
        #expect(controller.currentURL == nil)
    }
    
    @Test("formatTime static formatting helper across boundaries")
    func testFormatTimeHelper() {
        #expect(AudioPlayerController.formatTime(0) == "00:00")
        #expect(AudioPlayerController.formatTime(9.4) == "00:09")
        #expect(AudioPlayerController.formatTime(59.9) == "00:59")
        #expect(AudioPlayerController.formatTime(60.0) == "01:00")
        #expect(AudioPlayerController.formatTime(125.0) == "02:05")
        #expect(AudioPlayerController.formatTime(3600.0) == "1:00:00")
        #expect(AudioPlayerController.formatTime(3665.0) == "1:01:05")
        
        // Edge cases
        #expect(AudioPlayerController.formatTime(-10.0) == "00:00")
        #expect(AudioPlayerController.formatTime(.nan) == "00:00")
        #expect(AudioPlayerController.formatTime(.infinity) == "00:00")
    }
    
    @Test("formatTimeWithMilliseconds static formatting helper across boundaries")
    func testFormatTimeWithMillisecondsHelper() {
        #expect(AudioPlayerController.formatTimeWithMilliseconds(0) == "00:00.00")
        #expect(AudioPlayerController.formatTimeWithMilliseconds(1.25) == "00:01.25")
        #expect(AudioPlayerController.formatTimeWithMilliseconds(65.40) == "01:05.40")
        #expect(AudioPlayerController.formatTimeWithMilliseconds(3605.08) == "1:00:05.08")
        
        // Edge cases
        #expect(AudioPlayerController.formatTimeWithMilliseconds(-1.0) == "00:00.00")
        #expect(AudioPlayerController.formatTimeWithMilliseconds(.nan) == "00:00.00")
    }
    
    @Test("Playback rate clamping between 0.25 and 3.0")
    @MainActor
    func testPlaybackRateClamping() {
        let controller = AudioPlayerController()
        
        controller.setPlaybackRate(0.1)
        #expect(controller.playbackRate == 0.25)
        
        controller.setPlaybackRate(5.0)
        #expect(controller.playbackRate == 3.0)
        
        controller.setPlaybackRate(1.5)
        #expect(controller.playbackRate == 1.5)
    }
    
    @Test("Volume adjustments")
    @MainActor
    func testVolumeAdjustment() {
        let controller = AudioPlayerController()
        controller.volume = 0.5
        #expect(controller.volume == 0.5)
        
        controller.volume = 0.0
        #expect(controller.volume == 0.0)
    }
    
    @Test("Scrubbing lifecycle and idempotency")
    @MainActor
    func testScrubbingLifecycle() {
        let controller = AudioPlayerController()
        
        #expect(!controller.isScrubbing)
        controller.beginScrubbing()
        #expect(controller.isScrubbing)
        
        // Calling beginScrubbing while already scrubbing should not change state
        controller.beginScrubbing()
        #expect(controller.isScrubbing)
        
        controller.endScrubbing(resumePlayback: false)
        #expect(!controller.isScrubbing)
        
        // Ending again when not scrubbing is a no-op
        controller.endScrubbing(resumePlayback: false)
        #expect(!controller.isScrubbing)
    }
    
    @Test("Seek clamping when no media loaded")
    @MainActor
    func testSeekClampingWithoutMedia() {
        let controller = AudioPlayerController()
        
        controller.seek(to: -5.0)
        #expect(controller.currentTime == 0.0)
        
        controller.seek(to: 50.0)
        #expect(controller.currentTime == 0.0) // Clamped to duration (0.0)
    }
    
    @Test("Loading non-existent audio file throws AudioPlayerError.fileNotFound")
    @MainActor
    func testLoadNonExistentFileThrows() async {
        let controller = AudioPlayerController()
        let nonExistentURL = URL(fileURLWithPath: "/tmp/non_existent_audio_\(UUID().uuidString).wav")
        
        await #expect(throws: AudioPlayerError.self) {
            try await controller.load(url: nonExistentURL)
        }
    }
    
    @Test("Loading and controlling playback of actual synthesized WAV audio")
    @MainActor
    func testPlaybackLifecycleWithRealAudio() async throws {
        // Create 1.0s valid PCM mono WAV file
        let sampleRate = 44100
        let durationSeconds = 1.0
        let numSamples = Int(Double(sampleRate) * durationSeconds)
        let subchunk2Size = numSamples * 2
        let chunkSize = 36 + subchunk2Size
        
        var data = Data()
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        var cs = UInt32(chunkSize).littleEndian
        data.append(Data(bytes: &cs, count: 4))
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        data.append(contentsOf: [0x66, 0x6d, 0x74, 0x20]) // "fmt "
        var sc1 = UInt32(16).littleEndian
        data.append(Data(bytes: &sc1, count: 4))
        var af = UInt16(1).littleEndian
        data.append(Data(bytes: &af, count: 2))
        var nc = UInt16(1).littleEndian
        data.append(Data(bytes: &nc, count: 2))
        var sr = UInt32(sampleRate).littleEndian
        data.append(Data(bytes: &sr, count: 4))
        var br = UInt32(sampleRate * 2).littleEndian
        data.append(Data(bytes: &br, count: 4))
        var ba = UInt16(2).littleEndian
        data.append(Data(bytes: &ba, count: 2))
        var bps = UInt16(16).littleEndian
        data.append(Data(bytes: &bps, count: 2))
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        var sc2 = UInt32(subchunk2Size).littleEndian
        data.append(Data(bytes: &sc2, count: 4))
        
        for i in 0..<numSamples {
            let t = Double(i) / Double(sampleRate)
            let s = Int16(sin(2.0 * Double.pi * 440.0 * t) * 20000.0)
            var sampleLE = s.littleEndian
            data.append(Data(bytes: &sampleLE, count: 2))
        }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let controller = AudioPlayerController()
        try await controller.load(url: tempURL)
        
        #expect(controller.status == .ready)
        #expect(controller.duration > 0.8 && controller.duration < 1.2)
        #expect(controller.currentURL == tempURL)
        
        // Play
        controller.play()
        #expect(controller.isPlaying == true)
        #expect(controller.status == .playing)
        
        // Pause
        controller.pause()
        #expect(controller.isPlaying == false)
        #expect(controller.status == .paused)
        
        // Toggle play/pause
        controller.togglePlayPause()
        #expect(controller.isPlaying == true)
        controller.togglePlayPause()
        #expect(controller.isPlaying == false)
        
        // Seek within bounds
        controller.seek(to: 0.5)
        #expect(controller.currentTime == 0.5)
        
        // Skip forward
        controller.skipForward(by: 0.2)
        #expect(abs(controller.currentTime - 0.7) < 0.001)
        
        // Skip backward
        controller.skipBackward(by: 0.3)
        #expect(abs(controller.currentTime - 0.4) < 0.001)
        
        // Stop cleans up player and resets state
        controller.stop()
        #expect(controller.isPlaying == false)
        #expect(controller.status == .idle)
        #expect(controller.currentTime == 0.0)
        #expect(controller.duration == 0.0)
        #expect(controller.currentURL == nil)
    }
}
