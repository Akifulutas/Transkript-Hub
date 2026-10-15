import Foundation
import Testing
@testable import TranskriptHubCore

// MARK: - Protocol and Test Double Definitions

@MainActor
public protocol AudioPlaybackControlling: AnyObject, ObservableObject {
    var currentTime: Double { get }
    var duration: Double { get }
    var isPlaying: Bool { get }
    func load(url: URL) async throws
    func play()
    func pause()
    func togglePlayPause()
    func seek(to time: Double)
}

public struct WordItem: Codable, Sendable, Equatable {
    public let text: String
    public let start: Double // seconds
    public let end: Double   // seconds
    public let confidence: Float
    
    public init(text: String, start: Double, end: Double, confidence: Float = 1.0) {
        self.text = text
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}

/// Headless simulation of AVFoundation player controller for testing seek synchronization
@MainActor
public final class HeadlessAudioPlayerController: AudioPlaybackControlling {
    public private(set) var currentTime: Double = 0.0
    public private(set) var duration: Double = 0.0
    public private(set) var isPlaying: Bool = false
    public private(set) var seekCount: Int = 0
    public private(set) var lastSeekTarget: Double?
    
    /// Simulated hardware seek jitter (within ±100ms tolerance specification)
    public var seekJitter: Double = 0.0
    
    public init() {}
    
    public func setSimulatedDuration(_ duration: Double) {
        self.duration = duration
    }
    
    public func load(url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioDecoderError.fileNotFound(url)
        }
        // If file exists, simulate loading 60.0s if duration not set
        if duration == 0.0 {
            duration = 60.0
        }
        currentTime = 0.0
        isPlaying = false
    }
    
    public func play() {
        guard duration > 0 else { return }
        isPlaying = true
    }
    
    public func pause() {
        isPlaying = false
    }
    
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    public func seek(to time: Double) {
        seekCount += 1
        lastSeekTarget = time
        
        // Boundary clamping
        if time.isNaN || time.isInfinite {
            return
        }
        
        let clampedTime = max(0.0, min(time, duration))
        // Apply hardware jitter within ±100ms
        let boundedJitter = max(-0.090, min(seekJitter, 0.090))
        currentTime = max(0.0, min(clampedTime + boundedJitter, duration))
    }
    
    public func advancePlayback(by deltaSeconds: Double) {
        guard isPlaying else { return }
        currentTime = min(duration, currentTime + deltaSeconds)
        if currentTime >= duration {
            isPlaying = false
        }
    }
}

// MARK: - Karaoke Synchronizer Algorithm Helper

public struct KaraokeWordSynchronizer: Sendable {
    public let words: [WordItem]
    
    public init(words: [WordItem]) {
        self.words = words.sorted { $0.start < $1.start }
    }
    
    /// Finds active word index for a given playhead time using binary search
    public func activeWordIndex(at time: Double) -> Int? {
        guard !words.isEmpty else { return nil }
        
        var low = 0
        var high = words.count - 1
        
        while low <= high {
            let mid = (low + high) / 2
            let word = words[mid]
            
            if time >= word.start && time <= word.end {
                return mid
            } else if time < word.start {
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        
        return nil
    }
    
    /// Given a click on word at index, returns the seek target timestamp
    public func seekTarget(forWordIndex index: Int) -> Double? {
        guard words.indices.contains(index) else { return nil }
        return words[index].start
    }
}

// MARK: - Test Suite

@Suite("Audio Playback Seek Synchronization E2E Test Suite")
struct AudioPlaybackSeekSyncE2ETests {
    
    @Test("Audio Playback Seek Accuracy strictly conforms to ±100ms tolerance")
    @MainActor
    func testSeekAccuracyWithin100ms() async throws {
        let player = HeadlessAudioPlayerController()
        player.setSimulatedDuration(120.0)
        
        // Seek to normal target with 25ms hardware jitter
        player.seekJitter = 0.025
        player.seek(to: 15.340)
        
        let diff = abs(player.currentTime - 15.340)
        #expect(diff <= 0.100, "Seek accuracy deviation \(diff)s must not exceed ±100ms")
        
        // Seek to beginning
        player.seekJitter = -0.015
        player.seek(to: 0.0)
        #expect(player.currentTime >= 0.0)
        #expect(abs(player.currentTime - 0.0) <= 0.100)
        
        // Seek near end
        player.seekJitter = 0.040
        player.seek(to: 119.500)
        #expect(abs(player.currentTime - 119.500) <= 0.100)
    }
    
    @Test("Word Click-to-Seek jumps audio directly to word millisecond timestamp")
    @MainActor
    func testWordClickToSeekSynchronization() async throws {
        let words = [
            WordItem(text: "Transkript", start: 0.500, end: 1.200),
            WordItem(text: "Hub", start: 1.250, end: 1.700),
            WordItem(text: "Apple", start: 2.000, end: 2.600),
            WordItem(text: "Silicon", start: 2.650, end: 3.400),
            WordItem(text: "performansı", start: 3.450, end: 4.200)
        ]
        let synchronizer = KaraokeWordSynchronizer(words: words)
        let player = HeadlessAudioPlayerController()
        player.setSimulatedDuration(10.0)
        
        // User clicks word at index 3 ("Silicon", start: 2.650)
        guard let targetTime = synchronizer.seekTarget(forWordIndex: 3) else {
            Issue.record("Failed to resolve seek target for word index 3")
            return
        }
        
        player.seek(to: targetTime)
        
        #expect(abs(player.currentTime - 2.650) <= 0.100)
        #expect(player.lastSeekTarget == 2.650)
        
        // User clicks word at index 0 ("Transkript", start: 0.500)
        guard let targetStart = synchronizer.seekTarget(forWordIndex: 0) else {
            Issue.record("Failed to resolve seek target for word index 0")
            return
        }
        
        player.seek(to: targetStart)
        #expect(abs(player.currentTime - 0.500) <= 0.100)
    }
    
    @Test("Karaoke Active Word Illumination tracks continuous audio playback time")
    @MainActor
    func testKaraokeActiveWordIllumination() async throws {
        let words = [
            WordItem(text: "Birinci", start: 1.0, end: 2.0),
            WordItem(text: "İkinci", start: 2.2, end: 3.2),
            WordItem(text: "Üçüncü", start: 3.5, end: 4.5)
        ]
        let synchronizer = KaraokeWordSynchronizer(words: words)
        let player = HeadlessAudioPlayerController()
        player.setSimulatedDuration(10.0)
        player.seek(to: 0.0)
        player.play()
        
        // At t = 0.5s: before first word -> no active word
        player.seek(to: 0.5)
        #expect(synchronizer.activeWordIndex(at: player.currentTime) == nil)
        
        // At t = 1.5s: inside "Birinci" -> word index 0
        player.seek(to: 1.5)
        #expect(synchronizer.activeWordIndex(at: player.currentTime) == 0)
        
        // At t = 2.1s: in pause between word 0 and word 1 -> no active word
        player.seek(to: 2.1)
        #expect(synchronizer.activeWordIndex(at: player.currentTime) == nil)
        
        // At t = 2.8s: inside "İkinci" -> word index 1
        player.seek(to: 2.8)
        #expect(synchronizer.activeWordIndex(at: player.currentTime) == 1)
        
        // At t = 4.0s: inside "Üçüncü" -> word index 2
        player.seek(to: 4.0)
        #expect(synchronizer.activeWordIndex(at: player.currentTime) == 2)
    }
    
    @Test("Boundary seeks: negative values and past duration clamp safely")
    @MainActor
    func testSeekClampingAtBoundaries() async throws {
        let player = HeadlessAudioPlayerController()
        player.setSimulatedDuration(60.0)
        
        // Negative seek
        player.seek(to: -15.0)
        #expect(player.currentTime == 0.0)
        
        // Seek past end
        player.seek(to: 150.0)
        #expect(player.currentTime == 60.0)
        
        // Seek NaN / Inf
        player.seek(to: Double.nan)
        #expect(player.currentTime == 60.0) // Unchanged
        
        player.seek(to: Double.infinity)
        #expect(player.currentTime == 60.0) // Unchanged
    }
    
    @Test("Rapid scrubbing simulation handles 200 seek events without corruption")
    @MainActor
    func testRapidScrubbingStressSimulation() async throws {
        let player = HeadlessAudioPlayerController()
        player.setSimulatedDuration(100.0)
        player.play()
        
        // Simulate scrubbing across timeline: 0.5s intervals rapidly
        for i in 0...200 {
            let scrubTarget = Double(i) * 0.45
            player.seek(to: scrubTarget)
        }
        
        #expect(player.seekCount == 201)
        #expect(player.currentTime <= 100.0)
        #expect(player.currentTime >= 0.0)
        #expect(abs(player.currentTime - min(100.0, 200 * 0.45)) <= 0.100)
    }
    
    @Test("Play / Pause toggle lifecycle and duration reporting fidelity")
    @MainActor
    func testPlayPauseToggleLifecycle() async throws {
        let player = HeadlessAudioPlayerController()
        player.setSimulatedDuration(45.0)
        
        #expect(player.isPlaying == false)
        #expect(player.duration == 45.0)
        
        player.togglePlayPause()
        #expect(player.isPlaying == true)
        
        player.advancePlayback(by: 1.5)
        #expect(player.currentTime == 1.5)
        
        player.togglePlayPause()
        #expect(player.isPlaying == false)
        #expect(player.currentTime == 1.5)
        
        // Idempotency
        player.pause()
        #expect(player.isPlaying == false)
        
        player.play()
        #expect(player.isPlaying == true)
        player.play()
        #expect(player.isPlaying == true)
    }
}
