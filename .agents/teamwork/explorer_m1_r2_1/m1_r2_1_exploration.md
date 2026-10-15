# Architectural Investigation Report — Finding 1: `inFlightSeekTime` State Machine Trap & Observer Deadlock

**Explorer**: `explorer_m1_r2_1`  
**Milestone**: Milestone 1 (Audio Playback & Karaoke Sync) — Iteration 2  
**Target File**: `Sources/TranskriptHubCore/Audio/AudioPlayerController.swift`  
**Test Target**: `Tests/TranskriptHubCoreTests/AudioPlayerControllerTests.swift`  
**Issue Reference**: Reviewer 1 Report (`reviewer_m1_1/review_report.md`), Finding 1  

---

## 1. Executive Summary

During Iteration 1 code review, `reviewer_m1_1` identified a critical runtime defect in `AudioPlayerController.swift`:
If `seek(to:)` or `seek(to:tolerance:)` is called prior to loading an audio asset into `player`, `self.inFlightSeekTime` is assigned before the `player != nil` guard. Because `player` is `nil`, the method returns immediately without scheduling an AVPlayer seek completion block. 
Furthermore, neither `stop()` nor `load(url:)` resets `inFlightSeekTime`. Consequently, `inFlightSeekTime` becomes permanently trapped in an `Optional(0.0)` state.
When an audio asset is subsequently loaded and played, the periodic time observer:
```swift
guard !self.isScrubbing, self.inFlightSeekTime == nil else { return }
```
permanently fails on every 50ms tick. `self.currentTime` never updates during audio playback. This breaks:
1. Waveform visualizer playhead advancement (Voice Memos scrub bar stays stuck at 00:00).
2. Time readout indicators (`00:00`).
3. KaraokeTranscriptView active word illumination (active word calculation depends on `player.currentTime`).
4. Auto-scrolling across transcript segments.

This report documents the root cause, maps the complete state machine lifecycle, audits all 6 failure modes and edge cases, and provides the exact architectural fix and unit test specification for `worker_m1_2`.

---

## 2. Deep Root-Cause Analysis

### 2.1 Verbatim Code Inspection (`AudioPlayerController.swift`)

In `seek(to:)` (lines 159–175):
```swift
159: public func seek(to time: Double) {
160:     let clampedTime = max(0.0, min(time, duration))
161:     self.currentTime = clampedTime
162:     self.inFlightSeekTime = clampedTime
163:     
164:     guard let player = player else { return }
165:     let cmTime = CMTime(seconds: clampedTime, preferredTimescale: 1000)
166:     
167:     player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
168:         Task { @MainActor [weak self] in
169:             guard let self = self else { return }
170:             if self.inFlightSeekTime == clampedTime {
171:                 self.inFlightSeekTime = nil
172:             }
173:         }
174:     }
175: }
```

In `seek(to:tolerance:)` (lines 178–194):
```swift
178: public func seek(to time: Double, tolerance: CMTime) async -> Bool {
179:     let clampedTime = max(0.0, min(time, duration))
180:     self.currentTime = clampedTime
181:     self.inFlightSeekTime = clampedTime
182:     
183:     guard let player = player else { return false }
184:     let cmTime = CMTime(seconds: clampedTime, preferredTimescale: 1000)
185:     
186:     return await withCheckedContinuation { continuation in
187:         player.seek(to: cmTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
188:             Task { @MainActor [weak self] in
189:                 self?.inFlightSeekTime = nil
190:                 continuation.resume(returning: finished)
191:             }
192:         }
193:     }
194: }
```

In `stop()` (lines 196–213):
```swift
196: public func stop() {
197:     if let player = player, let token = timeObserverToken {
198:         player.removeTimeObserver(token)
199:         timeObserverToken = nil
200:     }
201:     if let endToken = endObserverToken {
202:         NotificationCenter.default.removeObserver(endToken)
203:         endObserverToken = nil
204:     }
205:     
206:     player?.pause()
207:     player = nil
208:     isPlaying = false
209:     currentTime = 0.0
210:     duration = 0.0
211:     status = .idle
212:     currentURL = nil
213: }
```

In `attachTimeObserver()` (lines 242–258):
```swift
242: private func attachTimeObserver() {
243:     guard let player = player else { return }
244:     
245:     timeObserverToken = player.addPeriodicTimeObserver(
246:         forInterval: timeUpdateInterval,
247:         queue: .main
248:     ) { [weak self] time in
249:         Task { @MainActor [weak self] in
250:             guard let self = self else { return }
251:             guard !self.isScrubbing, self.inFlightSeekTime == nil else { return }
252:             let sec = time.seconds
253:             if sec.isFinite && sec >= 0 {
254:                 self.currentTime = sec
255:             }
256:         }
257:     }
258: }
```

### 2.2 Trigger Tracing in Real-World UI Flows

This bug is not an exotic edge case; it is readily triggered in standard macOS user workflows:
1. **Empty Waveform Click/Drag**: In `WaveformVisualizerView.swift` (lines 110–127), the view attaches a `DragGesture(minimumDistance: 0)` that calls `player.seek(to: targetTime)`. If the user clicks anywhere in the player area before media has finished loading or when viewing an empty project, `player.seek(to:)` is fired.
2. **Keyboard Shortcut Dispatch**: In `ContentView.swift` (lines 140–143), transport shortcuts invoke `audioPlayer.seek(to:)`. Hitting a shortcut before media load traps `inFlightSeekTime`.
3. **Transcript Click Before Asset Load**: Clicking a word in `KaraokeTranscriptView` before audio is fully buffered invokes `player.seek(to: word.start)`.
4. **App Initialization & View Model Bindings**: Certain SwiftUI bindings or observers can query or reset slider positions on appear, passing `seek(to: 0.0)`.

Once triggered, any subsequent call to `load(url:)` and `play()` will result in silent playback failure where audio is audible, but the entire UI is deadlocked.

---

## 3. Comprehensive Failure Mode & Edge Case Matrix

| ID | Scenario | Current Behavior | Defect Classification | Required Architectural Behavior |
|---|---|---|---|---|
| **FM-1** | `seek(to:)` invoked before `load(url:)` | Sets `inFlightSeekTime = 0.0`, guards `player == nil`, returns. `inFlightSeekTime` never cleared. | **Critical Deadlock** | Guard player readiness first: if player/item is nil, ensure `inFlightSeekTime = nil` and return immediately without side effects. |
| **FM-2** | `seek(to:tolerance:) async` invoked before `load(url:)` | Sets `inFlightSeekTime = 0.0`, guards `player == nil`, returns `false`. Trapped. | **Critical Deadlock** | Guard player readiness first: return `false`, ensure `inFlightSeekTime = nil`. |
| **FM-3** | `stop()` called while a seek is in flight | Observers removed, `player = nil`, but `inFlightSeekTime` is preserved. | **State Leak** | `stop()` must explicitly reset `inFlightSeekTime = nil`, `isScrubbing = false`, `wasPlayingBeforeScrub = false`, and invalidate seek generations. |
| **FM-4** | `load(url:)` succeeds after seek or error | Initializes new `AVPlayer`, but does not reset `inFlightSeekTime`. | **State Leak** | `load(url:)` must explicitly reset `inFlightSeekTime = nil` and advance seek generation upon player initialization. |
| **FM-5** | Rapid seeks to identical timestamp (e.g. 2.5s -> drag -> 2.5s) | Seek 1 cancelled by AVPlayer; callback checks `inFlightSeekTime == 2.5`, which matches Seek 2's target, prematurely clearing `inFlightSeekTime` while Seek 2 is still in flight. | **Flicker/Jitter Race** | Introduce monotonic `seekGeneration: Int`. Callbacks only clear `inFlightSeekTime` if `seekGeneration == targetGeneration`. |
| **FM-6** | Extreme / Invalid inputs (`NaN`, `-infinity`, `+infinity`) | `max(0.0, min(time, duration))` can propagate NaN on IEEE-754 floats. | **Numeric Stability** | Explicit sanitization: clamp `NaN` and negative values to `0.0`, `> duration` to `duration`. |

---

## 4. Architectural Fix Formulation

### 4.1 Concept: Strict Readiness Guarding & Monotonic Generation Tracking

To completely eliminate both the deadlock and the cancellation races, the architectural fix introduces three core mechanisms:

1. **Player Readiness Verification**:
   A seek operation can only be created if:
   - `player != nil`
   - `player.currentItem != nil`
   - `status` is in a playable/seekable state (`.ready`, `.playing`, `.paused`, or `.ended`)
   If this guard fails, the controller explicitly ensures `inFlightSeekTime = nil` and returns early.

2. **Monotonic Seek Generation ID (`seekGeneration: Int`)**:
   Instead of comparing floating-point timestamps (`self.inFlightSeekTime == clampedTime`), the controller maintains an integer generation counter.
   - Each new seek increments `seekGeneration += 1`.
   - The completion block captures `targetGeneration`.
   - When AVPlayer finishes (whether completed or superseded), it only clears `inFlightSeekTime` if `self.seekGeneration == targetGeneration`.
   - `stop()` and `load(url:)` increment `seekGeneration += 1`, instantly invalidating all lingering completion handlers from prior players or seek attempts.

3. **Total State Cleansing in Lifecycle Hooks (`stop()` and `load()`)**:
   `stop()` and `load()` become definitive state sanitizers, resetting:
   - `inFlightSeekTime = nil`
   - `isScrubbing = false`
   - `wasPlayingBeforeScrub = false`
   - `seekGeneration += 1`

---

## 5. Proposed Implementation Diffs

### 5.1 `Sources/TranskriptHubCore/Audio/AudioPlayerController.swift`

```swift
// MARK: - Scrubbing & Seeking State
@Published public private(set) var isScrubbing: Bool = false
private var wasPlayingBeforeScrub: Bool = false
private var inFlightSeekTime: Double? = nil
private var seekGeneration: Int = 0

// In load(url: URL):
self.player = newPlayer
self.duration = seconds
self.currentTime = 0.0
self.isPlaying = false
self.status = .ready
self.inFlightSeekTime = nil
self.seekGeneration += 1

// MARK: - Seeking Implementations

public func seek(to time: Double) {
    guard let player = player, player.currentItem != nil,
          status == .ready || status == .playing || status == .paused || status == .ended else {
        self.inFlightSeekTime = nil
        return
    }
    
    let safeTime: Double
    if time.isNaN || time < 0 {
        safeTime = 0.0
    } else if time > duration {
        safeTime = duration
    } else {
        safeTime = time
    }
    
    self.currentTime = safeTime
    self.inFlightSeekTime = safeTime
    
    seekGeneration += 1
    let targetGeneration = seekGeneration
    
    let cmTime = CMTime(seconds: safeTime, preferredTimescale: 1000)
    player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if self.seekGeneration == targetGeneration {
                self.inFlightSeekTime = nil
            }
        }
    }
}

@discardableResult
public func seek(to time: Double, tolerance: CMTime) async -> Bool {
    guard let player = player, player.currentItem != nil,
          status == .ready || status == .playing || status == .paused || status == .ended else {
        self.inFlightSeekTime = nil
        return false
    }
    
    let safeTime: Double
    if time.isNaN || time < 0 {
        safeTime = 0.0
    } else if time > duration {
        safeTime = duration
    } else {
        safeTime = time
    }
    
    self.currentTime = safeTime
    self.inFlightSeekTime = safeTime
    
    seekGeneration += 1
    let targetGeneration = seekGeneration
    
    let cmTime = CMTime(seconds: safeTime, preferredTimescale: 1000)
    return await withCheckedContinuation { continuation in
        player.seek(to: cmTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    continuation.resume(returning: finished)
                    return
                }
                if self.seekGeneration == targetGeneration {
                    self.inFlightSeekTime = nil
                }
                continuation.resume(returning: finished)
            }
        }
    }
}

// In stop():
public func stop() {
    if let player = player, let token = timeObserverToken {
        player.removeTimeObserver(token)
        timeObserverToken = nil
    }
    if let endToken = endObserverToken {
        NotificationCenter.default.removeObserver(endToken)
        endObserverToken = nil
    }
    
    player?.pause()
    player = nil
    isPlaying = false
    currentTime = 0.0
    duration = 0.0
    status = .idle
    currentURL = nil
    isScrubbing = false
    wasPlayingBeforeScrub = false
    inFlightSeekTime = nil
    seekGeneration += 1
}
```

---

## 6. Unit Test Specification (`AudioPlayerControllerTests.swift`)

The following unit test must be incorporated into `Tests/TranskriptHubCoreTests/AudioPlayerControllerTests.swift` to assert that seeking before loading never freezes the periodic time observer on subsequent playback:

```swift
@Test("Seek prior to load does not trap inFlightSeekTime or freeze periodic time observer")
@MainActor
func testSeekBeforeLoadDoesNotFreezeTimeObserver() async throws {
    let controller = AudioPlayerController()
    
    // 1. Fire synchronous seeks on uninitialized player
    controller.seek(to: 5.0)
    #expect(controller.currentTime == 0.0)
    
    controller.seek(to: -10.0)
    #expect(controller.currentTime == 0.0)
    
    // 2. Fire async seek on uninitialized player
    let seekSuccess = await controller.seek(to: 3.0, tolerance: .zero)
    #expect(seekSuccess == false)
    #expect(controller.currentTime == 0.0)
    #expect(controller.isPlaying == false)
    #expect(controller.status == .idle)
    
    // 3. Synthesize valid 1.5s PCM mono WAV audio file
    let sampleRate = 44100
    let durationSeconds = 1.5
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
    
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("seek_freeze_test_\(UUID().uuidString).wav")
    try data.write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }
    
    // 4. Load synthesized media
    try await controller.load(url: tempURL)
    #expect(controller.status == .ready)
    #expect(controller.duration > 1.4 && controller.duration < 1.6)
    #expect(controller.currentTime == 0.0)
    
    // 5. Start playback
    controller.play()
    #expect(controller.isPlaying == true)
    #expect(controller.status == .playing)
    
    // 6. Await periodic time observer firing (250ms interval)
    try await Task.sleep(nanoseconds: 250_000_000)
    
    // 7. Verify time observation actively advanced (PROVES FIX)
    #expect(controller.currentTime > 0.03, "Periodic time observer must advance currentTime during playback; must not freeze due to pre-load seek")
    
    // 8. Test live seek and subsequent advancement
    controller.seek(to: 0.8)
    #expect(abs(controller.currentTime - 0.8) < 0.01)
    try await Task.sleep(nanoseconds: 150_000_000)
    #expect(controller.currentTime > 0.82)
    
    // 9. Verify stop and post-stop seek cleanliness
    controller.stop()
    #expect(controller.isPlaying == false)
    #expect(controller.status == .idle)
    #expect(controller.currentTime == 0.0)
    
    controller.seek(to: 1.0)
    #expect(controller.currentTime == 0.0)
    
    // 10. Reload and verify second playback session works cleanly
    try await controller.load(url: tempURL)
    controller.play()
    try await Task.sleep(nanoseconds: 200_000_000)
    #expect(controller.currentTime > 0.03)
    controller.stop()
}
```

---

## 7. Verification Method

To independently verify this fix:
1. Check that `AudioPlayerController.swift` implements the readiness guard and generation tracking.
2. Run `swift test --filter AudioPlayerControllerTests` to confirm the new test passes.
3. Run the entire test suite `swift test` to confirm 0 regressions across all 118 tests.
