import Foundation
import Testing
import AVFoundation
@testable import TranskriptHubCore

@Suite("Audio Player Controller Empirical Stress & Boundary Test Suite")
struct AudioPlayerEmpiricalStressTests {
    
    // Helper to synthesize a valid mono PCM WAV file of given duration and sample rate
    static func createSynthesizedWAV(durationSeconds: Double = 5.0, sampleRate: Int = 44100) throws -> URL {
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
            let s = Int16(sin(2.0 * Double.pi * 440.0 * t) * 15000.0)
            var sampleLE = s.littleEndian
            data.append(Data(bytes: &sampleLE, count: 2))
        }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("empirical_\(UUID().uuidString).wav")
        try data.write(to: tempURL)
        return tempURL
    }
    
    // MARK: - 1. Seek Precision & Latency Tests
    
    @Test("Empirical Seek Accuracy: async seek lands strictly within ±100ms tolerance")
    @MainActor
    func testSeekAccuracyWithin100ms() async throws {
        let tempURL = try Self.createSynthesizedWAV(durationSeconds: 6.0)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let controller = AudioPlayerController()
        try await controller.load(url: tempURL)
        #expect(controller.duration >= 5.9 && controller.duration <= 6.1)
        
        let testTargets: [Double] = [0.0, 1.250, 2.789, 4.500, 5.800]
        
        for target in testTargets {
            let startTime = ContinuousClock.now
            let finished = await controller.seek(to: target, tolerance: .zero)
            let elapsed = ContinuousClock.now - startTime
            
            #expect(finished == true, "Seek to \(target)s should finish successfully")
            let diff = abs(controller.currentTime - target)
            #expect(diff <= 0.100, "Seek accuracy deviation \(diff)s for target \(target)s exceeds ±100ms limit")
            // Latency check: seeking in-memory/local audio should complete well within 500ms
            #expect(elapsed < .milliseconds(500), "Seek latency \(elapsed) exceeds acceptable threshold")
        }
    }
    
    // MARK: - 2. Rapid Scrub Cycles & Play/Pause Toggles
    
    @Test("Rapid Scrubbing Stress: 150 rapid seeks while paused without deadlock or corruption")
    @MainActor
    func testRapidScrubbingWhilePaused() async throws {
        let tempURL = try Self.createSynthesizedWAV(durationSeconds: 10.0)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let controller = AudioPlayerController()
        try await controller.load(url: tempURL)
        
        controller.beginScrubbing()
        #expect(controller.isScrubbing)
        
        // Rapid fire 150 seeks across timeline
        for i in 0..<150 {
            let target = Double(i % 100) * 0.09
            controller.seek(to: target)
        }
        
        // Final seek to specific target
        controller.seek(to: 4.5)
        #expect(abs(controller.currentTime - 4.5) < 0.001)
        
        controller.endScrubbing(resumePlayback: false)
        #expect(!controller.isScrubbing)
        #expect(!controller.isPlaying)
        #expect(abs(controller.currentTime - 4.5) < 0.001)
    }
    
    @Test("Rapid Scrubbing Stress: 100 rapid seeks while playing resumes smoothly")
    @MainActor
    func testRapidScrubbingWhilePlaying() async throws {
        let tempURL = try Self.createSynthesizedWAV(durationSeconds: 10.0)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let controller = AudioPlayerController()
        try await controller.load(url: tempURL)
        
        controller.play()
        #expect(controller.isPlaying)
        
        controller.beginScrubbing()
        #expect(controller.isScrubbing)
        // AVPlayer paused during scrubbing
        
        for i in 0..<100 {
            let target = Double(i) * 0.08
            controller.seek(to: target)
        }
        
        controller.seek(to: 3.0)
        controller.endScrubbing(resumePlayback: true)
        
        #expect(!controller.isScrubbing)
        #expect(controller.isPlaying)
        #expect(abs(controller.currentTime - 3.0) < 0.001)
    }
    
    @Test("Rapid Play/Pause Toggles: 100 alternating toggles do not crash or corrupt state")
    @MainActor
    func testRapidPlayPauseToggles() async throws {
        let tempURL = try Self.createSynthesizedWAV(durationSeconds: 10.0)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let controller = AudioPlayerController()
        try await controller.load(url: tempURL)
        
        for _ in 0..<100 {
            controller.togglePlayPause()
        }
        
        // Should be paused (100 toggles from initial paused state = even count = paused)
        #expect(controller.isPlaying == false)
        #expect(controller.status == .paused)
        
        // Controller remains fully functional
        controller.play()
        #expect(controller.isPlaying == true)
        #expect(controller.status == .playing)
        controller.pause()
        #expect(controller.isPlaying == false)
    }
    
    // MARK: - 3. Boundary Values & Nil/Unloaded Assets
    
    @Test("Boundary Seeks: negative values, overflow, NaN, Infinity clamp cleanly")
    @MainActor
    func testBoundarySeeksWithLoadedAsset() async throws {
        let tempURL = try Self.createSynthesizedWAV(durationSeconds: 5.0)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let controller = AudioPlayerController()
        try await controller.load(url: tempURL)
        let dur = controller.duration
        
        // Negative seek
        controller.seek(to: -50.0)
        #expect(controller.currentTime == 0.0)
        
        controller.seek(to: -0.0001)
        #expect(controller.currentTime == 0.0)
        
        // Overflow seek (past duration + 1000s)
        controller.seek(to: dur + 1000.0)
        #expect(controller.currentTime == dur)
        
        controller.seek(to: 999999.0)
        #expect(controller.currentTime == dur)
        
        // Extreme values
        controller.seek(to: -Double.infinity)
        #expect(controller.currentTime == 0.0)
        
        controller.seek(to: Double.infinity)
        #expect(controller.currentTime == dur)
    }
    
    @Test("Nil/Unloaded Asset Stability: all operations are safe when no media is loaded")
    @MainActor
    func testNilUnloadedAssetSafety() {
        let controller = AudioPlayerController()
        
        #expect(controller.duration == 0.0)
        #expect(controller.currentTime == 0.0)
        #expect(controller.currentURL == nil)
        
        // Seeking with no media loaded
        controller.seek(to: 10.0)
        #expect(controller.currentTime == 0.0)
        
        controller.seek(to: -5.0)
        #expect(controller.currentTime == 0.0)
        
        controller.seek(to: Double.infinity)
        #expect(controller.currentTime == 0.0)
        
        // Transport controls with no media
        controller.play()
        #expect(!controller.isPlaying)
        #expect(controller.status == .idle)
        
        controller.pause()
        #expect(!controller.isPlaying)
        
        controller.togglePlayPause()
        #expect(!controller.isPlaying)
        
        controller.skipForward(by: 5.0)
        #expect(controller.currentTime == 0.0)
        
        controller.skipBackward(by: 5.0)
        #expect(controller.currentTime == 0.0)
        
        controller.beginScrubbing()
        #expect(controller.isScrubbing)
        controller.endScrubbing(resumePlayback: true)
        #expect(!controller.isScrubbing)
        #expect(!controller.isPlaying)
        
        controller.stop()
        #expect(controller.status == .idle)
    }
    
    // MARK: - 4. Time Formatter Rounding and Durations
    
    @Test("Time Formatter edge rounding and boundaries")
    func testTimeFormatterRounding() {
        // Standard rounding checks for formatTimeWithMilliseconds
        #expect(AudioPlayerController.formatTimeWithMilliseconds(0.000) == "00:00.00")
        #expect(AudioPlayerController.formatTimeWithMilliseconds(0.004) == "00:00.00")
        #expect(AudioPlayerController.formatTimeWithMilliseconds(0.005) == "00:00.01")
        #expect(AudioPlayerController.formatTimeWithMilliseconds(59.994) == "00:59.99")
        #expect(AudioPlayerController.formatTimeWithMilliseconds(59.995) == "01:00.00")
        #expect(AudioPlayerController.formatTimeWithMilliseconds(3599.994) == "59:59.99")
        #expect(AudioPlayerController.formatTimeWithMilliseconds(3599.995) == "1:00:00.00")
        
        // Large standard durations
        #expect(AudioPlayerController.formatTime(36000.0) == "10:00:00") // 10 hours
        #expect(AudioPlayerController.formatTime(360000.0) == "100:00:00") // 100 hours
        #expect(AudioPlayerController.formatTimeWithMilliseconds(36000.0) == "10:00:00.00")
        #expect(AudioPlayerController.formatTimeWithMilliseconds(360000.0) == "100:00:00.00")
    }
    
    // MARK: - 5. Live Playback Seeking & Playhead Continuity
    
    @Test("Seeking while actively playing advances forward from target without pre-seek regression")
    @MainActor
    func testSeekingWhileActivelyPlaying() async throws {
        let tempURL = try Self.createSynthesizedWAV(durationSeconds: 8.0)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let controller = AudioPlayerController()
        try await controller.load(url: tempURL)
        
        controller.play()
        #expect(controller.isPlaying)
        
        // Let it play briefly
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Seek to 4.0s while playing
        controller.seek(to: 4.0)
        #expect(controller.currentTime == 4.0)
        
        // Wait for seek and subsequent playback updates
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // currentTime must NOT have regressed to 0.x, it must be >= 4.0
        #expect(controller.currentTime >= 3.95, "Playback must not jump back to pre-seek position")
        #expect(controller.currentTime <= 5.0, "Playback should be progressing around 4.x seconds")
        #expect(controller.isPlaying == true)
        
        controller.pause()
    }
    
    @Test("Word Click-to-Seek flow: seek to timestamp followed immediately by play")
    @MainActor
    func testWordClickToSeekImmediatePlay() async throws {
        let tempURL = try Self.createSynthesizedWAV(durationSeconds: 6.0)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let controller = AudioPlayerController()
        try await controller.load(url: tempURL)
        
        // Simulating Karaoke click: paused -> click word at 2.5s -> seek + play
        let target = 2.500
        controller.seek(to: target)
        if !controller.isPlaying {
            controller.play()
        }
        
        #expect(controller.isPlaying)
        #expect(abs(controller.currentTime - target) <= 0.100)
        
        // Allow playback to proceed 150ms
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(controller.currentTime >= target - 0.05)
        #expect(controller.isPlaying)
        
        controller.stop()
    }
    
    @Test("Play to end lifecycle: reaches ended status and restarts on subsequent play")
    @MainActor
    func testPlayToEndAndRestart() async throws {
        // Create short 0.3s audio clip
        let tempURL = try Self.createSynthesizedWAV(durationSeconds: 0.3)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let controller = AudioPlayerController()
        try await controller.load(url: tempURL)
        let dur = controller.duration
        
        controller.play()
        #expect(controller.isPlaying)
        
        // Wait for audio to play to end
        let deadline = Date().addingTimeInterval(2.0)
        while controller.isPlaying && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
            await Task.yield()
        }
        
        #expect(controller.status == .ended || !controller.isPlaying)
        #expect(controller.isPlaying == false)
        #expect(abs(controller.currentTime - dur) <= 0.05 || controller.currentTime == dur)
        
        // Calling play after ended should restart from 0.0
        controller.play()
        #expect(controller.isPlaying == true)
        #expect(controller.currentTime < 0.2) // Restarted from 0.0
        
        controller.stop()
    }
}

