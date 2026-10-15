import Foundation
import Testing
import AVFoundation
@testable import TranskriptHubCore

@Suite("Challenger 1 Empirical Stress Test Suite (Iteration 2)")
struct Challenger1Iteration2StressTests {
    
    // Helper to synthesize a valid mono PCM WAV file
    static func createSynthesizedWAV(durationSeconds: Double = 2.0, sampleRate: Int = 44100) throws -> URL {
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
            let s = Int16(sin(2.0 * Double.pi * 440.0 * t) * 16000.0)
            var sampleLE = s.littleEndian
            data.append(Data(bytes: &sampleLE, count: 2))
        }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("c1_stress_\(UUID().uuidString).wav")
        try data.write(to: tempURL)
        return tempURL
    }
    
    // MARK: - Finding 1 Stress Test: Pre-Load Seek Spamming
    
    @Test("Finding 1: Pre-load seek spamming (100 seeks) does not trap inFlightSeekTime and subsequent playback advances normally")
    @MainActor
    func testPreLoadSeekSpammingStress() async throws {
        let controller = AudioPlayerController()
        
        // 1. Spam seek(to: 10.0) 100 times before loading audio
        for _ in 0..<100 {
            controller.seek(to: 10.0)
            #expect(controller.currentTime == 0.0)
        }
        
        // 2. Spam edge-case seeks (negative, infinity, NaN) and skips
        for _ in 0..<20 {
            controller.skipForward(by: 10.0)
            controller.skipBackward(by: 5.0)
            controller.seek(to: -50.0)
            controller.seek(to: .infinity)
            controller.seek(to: -.infinity)
            controller.seek(to: .nan)
            #expect(controller.currentTime == 0.0)
        }
        
        // 3. Spam async seeks before loading audio
        for _ in 0..<20 {
            let success = await controller.seek(to: 10.0, tolerance: .zero)
            #expect(success == false)
            #expect(controller.currentTime == 0.0)
        }
        
        #expect(controller.status == .idle)
        #expect(controller.isPlaying == false)
        
        // 4. Load synthesized 2.0s WAV audio
        let tempURL = try Self.createSynthesizedWAV(durationSeconds: 2.0)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await controller.load(url: tempURL)
        #expect(controller.status == .ready)
        #expect(controller.duration >= 1.9 && controller.duration <= 2.1)
        #expect(controller.currentTime == 0.0)
        
        // 5. Start playback
        controller.play()
        #expect(controller.isPlaying == true)
        #expect(controller.status == .playing)
        
        // 6. Monitor periodic time observer updates (must advance normally, proving inFlightSeekTime is not trapped)
        var advanced = false
        for _ in 0..<20 {
            if controller.currentTime > 0.05 {
                advanced = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
        
        #expect(advanced, "Periodic time observer MUST advance currentTime after pre-load seek spam; inFlightSeekTime was NOT trapped.")
        #expect(controller.currentTime > 0.05)
        
        // 7. Perform live seek while playing and verify continuation
        controller.seek(to: 1.0)
        #expect(abs(controller.currentTime - 1.0) < 0.05)
        
        var seekAdvanced = false
        for _ in 0..<20 {
            if controller.currentTime > 1.03 {
                seekAdvanced = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
        #expect(seekAdvanced, "Playback MUST continue advancing past seek position 1.0")
        #expect(controller.currentTime > 1.03)
        
        controller.stop()
        #expect(controller.status == .idle)
        #expect(controller.currentTime == 0.0)
        #expect(controller.isPlaying == false)
    }
    
    // MARK: - Finding 2 Stress Test: Deinit Teardown with 100 Instances
    
    @Test("Finding 2A: Allocate and immediately drop 100 AudioPlayerController instances WITHOUT load/play: zero leaks, zero crashes")
    @MainActor
    func testDeinitTeardown100InstancesWithoutLoadOrPlay() {
        class WeakBox {
            weak var value: AudioPlayerController?
            init(_ value: AudioPlayerController) {
                self.value = value
            }
        }
        
        var weakBoxes: [WeakBox] = []
        weakBoxes.reserveCapacity(100)
        
        for _ in 0..<100 {
            let controller = AudioPlayerController()
            #expect(controller.status == .idle)
            weakBoxes.append(WeakBox(controller))
            // Controller falls out of scope here
        }
        
        // Verify all 100 instances deallocated cleanly under ARC
        let leakedCount = weakBoxes.filter { $0.value != nil }.count
        #expect(leakedCount == 0, "All 100 idle AudioPlayerController instances must be deallocated; leaked: \(leakedCount)")
        
        // Trigger notification center to ensure no stray handlers execute
        NotificationCenter.default.post(
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }
    
    @Test("Finding 2B: Allocate, load audio, play, and immediately drop 100 AudioPlayerController instances: zero observer leaks, zero crashes")
    @MainActor
    func testDeinitTeardown100InstancesWithLoadAndPlay() async throws {
        let tempURL = try Self.createSynthesizedWAV(durationSeconds: 1.0)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        class WeakBox {
            weak var value: AudioPlayerController?
            init(_ value: AudioPlayerController) {
                self.value = value
            }
        }
        
        var weakBoxes: [WeakBox] = []
        weakBoxes.reserveCapacity(100)
        
        for _ in 0..<100 {
            do {
                let controller = AudioPlayerController()
                try await controller.load(url: tempURL)
                controller.play()
                #expect(controller.isPlaying == true)
                weakBoxes.append(WeakBox(controller))
                // Drop controller immediately without calling stop()
            }
        }
        
        // Give runloop / ARC a breath to finalize deallocations
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // Verify all 100 instances deallocated cleanly
        let leakedCount = weakBoxes.filter { $0.value != nil }.count
        #expect(leakedCount == 0, "All 100 loaded & playing AudioPlayerController instances must be deallocated via isolated deinit; leaked: \(leakedCount)")
        
        // Fire NotificationCenter event multiple times to confirm zero zombie handler crashes
        for _ in 0..<10 {
            NotificationCenter.default.post(
                name: .AVPlayerItemDidPlayToEndTime,
                object: nil
            )
        }
    }
    
    @Test("Finding 2C: Allocate, load, play, explicit stop(), and drop 100 AudioPlayerController instances: zero leaks, zero crashes")
    @MainActor
    func testDeinitTeardown100InstancesWithExplicitStop() async throws {
        let tempURL = try Self.createSynthesizedWAV(durationSeconds: 1.0)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        class WeakBox {
            weak var value: AudioPlayerController?
            init(_ value: AudioPlayerController) {
                self.value = value
            }
        }
        
        var weakBoxes: [WeakBox] = []
        weakBoxes.reserveCapacity(100)
        
        for _ in 0..<100 {
            let controller = AudioPlayerController()
            try await controller.load(url: tempURL)
            controller.play()
            controller.stop()
            weakBoxes.append(WeakBox(controller))
        }
        
        let leakedCount = weakBoxes.filter { $0.value != nil }.count
        #expect(leakedCount == 0, "All 100 stopped AudioPlayerController instances must deallocate cleanly; leaked: \(leakedCount)")
    }
    
    // MARK: - Additional Adversarial Stress Tests
    
    @Test("Finding 1 Edge: Scrubbing state manipulation before load does not corrupt state after load")
    @MainActor
    func testPreLoadScrubbingAndSeekingLifecycle() async throws {
        let controller = AudioPlayerController()
        
        // Manipulate scrubbing before loading media
        controller.beginScrubbing()
        #expect(controller.isScrubbing == true)
        
        controller.seek(to: 5.0)
        #expect(controller.currentTime == 0.0)
        
        controller.endScrubbing(resumePlayback: true)
        #expect(controller.isScrubbing == false)
        #expect(controller.isPlaying == false)
        
        // Load media and verify state is pristine
        let tempURL = try Self.createSynthesizedWAV(durationSeconds: 1.5)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        try await controller.load(url: tempURL)
        #expect(controller.status == .ready)
        #expect(controller.isScrubbing == false)
        #expect(controller.currentTime == 0.0)
        
        controller.play()
        #expect(controller.isPlaying == true)
        
        var advanced = false
        for _ in 0..<15 {
            if controller.currentTime > 0.05 {
                advanced = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(advanced)
        controller.stop()
    }
    
    @Test("Finding 1 & 2 Lifecycle: Pre-load seek followed by back-to-back reloads without stop() remains stable")
    @MainActor
    func testPreLoadSeekThenMultipleReloadsCycle() async throws {
        let tempURL1 = try Self.createSynthesizedWAV(durationSeconds: 1.0)
        let tempURL2 = try Self.createSynthesizedWAV(durationSeconds: 1.5)
        let tempURL3 = try Self.createSynthesizedWAV(durationSeconds: 2.0)
        defer {
            try? FileManager.default.removeItem(at: tempURL1)
            try? FileManager.default.removeItem(at: tempURL2)
            try? FileManager.default.removeItem(at: tempURL3)
        }
        
        let controller = AudioPlayerController()
        
        // Seek prior to any load
        controller.seek(to: 5.0)
        
        // Load 1st media, play, seek
        try await controller.load(url: tempURL1)
        controller.play()
        controller.seek(to: 0.3)
        
        // Load 2nd media directly without calling stop()
        try await controller.load(url: tempURL2)
        #expect(controller.status == .ready)
        #expect(controller.currentTime == 0.0)
        controller.play()
        
        var advanced = false
        for _ in 0..<15 {
            if controller.currentTime > 0.05 {
                advanced = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(advanced)
        
        // Load 3rd media
        try await controller.load(url: tempURL3)
        controller.play()
        controller.seek(to: 0.5)
        
        var advanced3rd = false
        for _ in 0..<15 {
            if controller.currentTime > 0.53 {
                advanced3rd = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(advanced3rd)
        controller.stop()
    }
}
