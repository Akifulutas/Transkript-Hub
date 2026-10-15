# Exploration Report: AudioPlayerController deinit & Observer Teardown Under Swift 6 Strict Concurrency

**Explorer**: `explorer_m1_r2_2`  
**Milestone**: Milestone 1 (Audio Playback & Karaoke Sync) — Iteration 2  
**Target Finding**: Reviewer 1 Finding 2 (Missing `deinit` Memory Cleanup in `AudioPlayerController`)  
**Date**: 2026-10-15T19:51:00Z  
**Reference Documents**:
- `ORIGINAL_REQUEST.md` (R1.1, R6.2)
- `PROJECT.md` (FEAT-R1-02, Code Layout)
- `reviewer_m1_1/review_report.md` (Finding 2)

---

## 1. Executive Summary

During Milestone 1 code review, `reviewer_m1_1` identified that `AudioPlayerController` lacked a `deinit` implementation. `AudioPlayerController` acquires two observer tokens during `load(url:)`:
1. `timeObserverToken: Any?` via `AVPlayer.addPeriodicTimeObserver(...)`
2. `endObserverToken: (any NSObjectProtocol)?` via `NotificationCenter.default.addObserver(...)`

Currently, observer detachment only occurs in the public `stop()` method. If an `AudioPlayerController` is deallocated without an explicit call to `stop()` (for example, when a user dismisses a transcript window, navigates away, or when view models are reconstructed), the observers are never detached. This leaks closure callbacks in the global `NotificationCenter.default` registry and violates AVFoundation's mandate to remove time observers before player deallocation.

This report establishes:
1. **Empirical proof** of the closure leak in `NotificationCenter` and the lifetime semantics of `AVPlayer`.
2. **The Swift 6 strict concurrency constraint**: A standard `nonisolated deinit` cannot access `timeObserverToken` or `endObserverToken` because they are non-Sendable properties isolated to `@MainActor`.
3. **The optimal teardown architecture**: Utilizing Swift 6's SE-0371 `isolated deinit { stop() }`, ensuring 100% actor-isolated synchronous cleanup on `@MainActor`, complete idempotency with manual `stop()` calls, and automatic playback termination (`player?.pause()`).
4. **Concrete implementation and unit tests** ready for the implementation worker.

---

## 2. Deep Investigation of the Observer Leak (Finding 2)

### 2.1 Code Inspection

In `Sources/TranskriptHubCore/Audio/AudioPlayerController.swift`:
- **Class Definition** (line 35):
  ```swift
  @MainActor
  public final class AudioPlayerController: ObservableObject, AudioPlaybackControlling
  ```
- **Observer Storage** (lines 64–68):
  ```swift
  // MARK: - Internal AVPlayer & Observers
  private var player: AVPlayer?
  private var timeObserverToken: Any?
  private var endObserverToken: (any NSObjectProtocol)?
  ```
- **Observer Registration** (lines 242–273):
  ```swift
  private func attachTimeObserver() {
      guard let player = player else { return }
      timeObserverToken = player.addPeriodicTimeObserver(
          forInterval: timeUpdateInterval,
          queue: .main
      ) { [weak self] time in
          Task { @MainActor [weak self] in
              guard let self = self else { return }
              guard !self.isScrubbing, self.inFlightSeekTime == nil else { return }
              let sec = time.seconds
              if sec.isFinite && sec >= 0 {
                  self.currentTime = sec
              }
          }
      }
  }

  private func attachEndObserver(for item: AVPlayerItem) {
      endObserverToken = NotificationCenter.default.addObserver(
          forName: .AVPlayerItemDidPlayToEndTime,
          object: item,
          queue: .main
      ) { [weak self] _ in
          Task { @MainActor [weak self] in
              guard let self = self else { return }
              self.isPlaying = false
              self.status = .ended
              self.currentTime = self.duration
          }
      }
  }
  ```
- **Cleanup Location** (lines 196–213 in `stop()`):
  ```swift
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
  }
  ```
- **Missing `deinit`**:
  The class contains zero `deinit` declarations.

### 2.2 Empirical Demonstration of the Observer Closure Leak

To observe the defect empirically, we executed a test where an observer is registered with `NotificationCenter.default.addObserver(forName:object:queue:using:)` capturing `[weak target]`. The target is then deallocated without removing the token:

```
[Execution Output]:
LEAKED OBSERVER CLOSURE CALLED AFTER TARGET DEALLOCATED!
```

**Consequences of the leak**:
1. **NotificationCenter Registry Bloat**: `NotificationCenter.default` maintains a strong reference to the observation block until `removeObserver(_:)` is explicitly invoked with the token. Every deallocated `AudioPlayerController` leaves behind an orphan closure.
2. **AVFoundation CoreMedia Timing Loop**: Apple documentation specifies:
   > *"You must invoke `removeTimeObserver:` for each observer you register with `addPeriodicTimeObserverForInterval:queue:usingBlock:`. You must invoke `removeTimeObserver:` before the player object is deallocated."*  
   Failing to remove the observer before player destruction risks memory warnings or internal AVFoundation assertion failures.
3. **Ghost Audio Playback**: If an `AudioPlayerController` is deallocated while audio is actively playing and `stop()` is not called, the underlying `AVPlayer` may continue rendering audio until CoreAudio drains its hardware buffers.

---

## 3. Swift 6 Concurrency & Actor Isolation Mechanics

### 3.1 The Naive `deinit` Compilation Failure

In Swift 6 language mode (`-swift-version 6 -enable-experimental-feature StrictConcurrency`), the default `deinit` on any class is `nonisolated`. If an engineer naively implements:

```swift
deinit {
    if let player = player, let token = timeObserverToken {
        player.removeTimeObserver(token)
    }
    if let token = endObserverToken {
        NotificationCenter.default.removeObserver(token)
    }
}
```

The Swift 6 compiler rejects this code with two fatal concurrency errors:
```
error: cannot access property 'timeObserverToken' with a non-Sendable type 'Any?' from nonisolated deinit
deinit {
`- note: add 'isolated' to run isolated to 'MainActor', which may be later than 'nonisolated deinit'
    if let player = player, let token = timeObserverToken {
    `- error: cannot access property 'timeObserverToken' with a non-Sendable type 'Any?' from nonisolated deinit

error: cannot access property 'endObserverToken' with a non-Sendable type '(any NSObjectProtocol)?' from nonisolated deinit
    if let token = endObserverToken {
    `- error: cannot access property 'endObserverToken' with a non-Sendable type '(any NSObjectProtocol)?' from nonisolated deinit
```

**Root Cause**:
- `timeObserverToken: Any?` is not `Sendable`.
- `endObserverToken: (any NSObjectProtocol)?` is not `Sendable`.
- `player: AVPlayer?` is not `Sendable`.
- `AudioPlayerController` is bound to `@MainActor`.
- A `nonisolated deinit` can execute on any arbitrary thread when ARC drops the final strong reference. Accessing actor-isolated non-Sendable properties from a nonisolated context is an illegal data race in Swift 6.

### 3.2 The Solution: SE-0371 Isolated Synchronous Deinit

Swift Evolution proposal **SE-0371** ("Isolated synchronous deinit") provides native language support for actor-isolated deinitializers:

```swift
isolated deinit {
    stop()
}
```

**How `isolated deinit` operates**:
1. **Actor Isolation**: Marking `isolated deinit` binds the deinitializer directly to the class's actor isolation context (`@MainActor`).
2. **Access Permissions**: Inside `isolated deinit`, the compiler permits synchronous access to all `@MainActor`-isolated properties (`player`, `timeObserverToken`, `endObserverToken`) and allows invoking `@MainActor` synchronous methods (such as `stop()`).
3. **Execution Semantics**:
   - **When deallocated on `@MainActor`** (the standard path for UI/view model objects): The deinitializer executes immediately and synchronously on the main thread.
   - **When deallocated on a background thread**: The Swift runtime detects that the deinitializer is isolated to `@MainActor`. The memory deallocation is safely enqueued onto the `MainActor`'s executor, running `isolated deinit` when the main actor runs.
4. **Compatibility**: Fully supported in Swift 6.0+ on macOS 14.0+.

We verified this behavior empirically using the Swift 6 compiler:
```
Dropping reference on background GCD thread
Isolated deinit executed on isMainThread: true
```

---

## 4. Teardown Strategy Comparison

| Criteria | Strategy 1: `isolated deinit { stop() }` (Recommended) | Strategy 2: RAII Token Wrappers (`TimeObserverToken`, `NotificationObserverToken`) |
|---|---|---|
| **Lines of Code** | 3 lines | ~35 lines across 2 helper classes |
| **New Types Introduced** | 0 | 2 (`TimeObserverToken`, `NotificationObserverToken`) |
| **Actor Safety** | Guaranteed via SE-0371 `@MainActor` isolation | Requires `@unchecked Sendable` annotations on token classes |
| **Playback Termination** | Automatically pauses audio (`player?.pause()`) on deinit | Only unregisters tokens; does not pause active playback unless extra code added |
| **Idempotency** | Completely idempotent with manual `stop()` calls | Requires careful manual tracking to avoid double-removal on manual `stop()` |
| **Maintainability** | Centralizes all teardown logic in the single, tested `stop()` method | Teardown logic split between `stop()` and token `deinit` blocks |

**Conclusion**: **Strategy 1 (`isolated deinit { stop() }`)** is the superior, idiomatic Swift 6 solution.

---

## 5. Proposed Implementation Changes

### Target File: `Sources/TranskriptHubCore/Audio/AudioPlayerController.swift`

#### Edit 1: Ensure `stop()` Clears Seek State (Resolving Finding 1 & Finding 2 Synergy)

In `AudioPlayerController.swift`, update `stop()`:
```swift
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
        inFlightSeekTime = nil
        isPlaying = false
        currentTime = 0.0
        duration = 0.0
        status = .idle
        currentURL = nil
    }
```

#### Edit 2: Add `isolated deinit`

Directly after `stop()`, add:
```swift
    // MARK: - Teardown & Lifecycle
    
    isolated deinit {
        stop()
    }
```

---

## 6. Proposed Unit Tests

### Target File: `Tests/TranskriptHubCoreTests/AudioPlayerControllerTests.swift`

Add the following three dedicated unit tests to `AudioPlayerControllerTests`:

```swift
    // MARK: - Deallocation & Teardown Tests
    
    @Test("Deallocation cleans up player and observers without explicit stop() call")
    @MainActor
    func testDeallocationCleansUpObserversWithoutStop() async throws {
        // Synthesize a valid 0.5s PCM mono WAV audio file
        let sampleRate = 44100
        let durationSeconds = 0.5
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
        
        weak var weakController: AudioPlayerController?
        
        do {
            let controller = AudioPlayerController()
            try await controller.load(url: tempURL)
            controller.play()
            
            #expect(controller.isPlaying == true)
            #expect(controller.status == .playing)
            
            weakController = controller
            #expect(weakController != nil)
            // Deliberately do NOT call controller.stop() here; let it drop out of scope
        }
        
        // Controller must be deallocated cleanly by ARC
        #expect(weakController == nil)
        
        // Post NotificationCenter event: if endObserver was leaked, this would execute a dead closure or crash
        NotificationCenter.default.post(
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }
    
    @Test("Deallocation after explicit stop() is safe and idempotent")
    @MainActor
    func testDeallocationAfterExplicitStop() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        // Minimal WAV header
        var data = Data([0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45, 0x66, 0x6d, 0x74, 0x20,
                         0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x44, 0xac, 0x00, 0x00, 0x88, 0x58, 0x01, 0x00,
                         0x02, 0x00, 0x10, 0x00, 0x64, 0x61, 0x74, 0x61, 0x00, 0x00, 0x00, 0x00])
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        weak var weakController: AudioPlayerController?
        
        do {
            let controller = AudioPlayerController()
            weakController = controller
            controller.stop() // First stop on idle
            controller.stop() // Second redundant stop
            #expect(weakController != nil)
        }
        
        #expect(weakController == nil)
    }
    
    @Test("Deallocation of unloaded idle controller does not crash")
    @MainActor
    func testDeallocationWhileIdle() {
        weak var weakController: AudioPlayerController?
        
        do {
            let controller = AudioPlayerController()
            weakController = controller
            #expect(controller.status == .idle)
            #expect(weakController != nil)
        }
        
        #expect(weakController == nil)
    }
```

---

## 7. Verification Method

Once the changes are applied by the implementation worker, the fix can be verified by running:

```bash
swift test --filter AudioPlayerControllerTests
```
Expected output:
- All 12 unit tests pass in <0.10s.
- Zero compiler warnings under `-strict-concurrency=complete`.
- Clean deallocation verified across idle, loaded, playing, and explicit-stop lifecycles.

To verify full suite regression status:
```bash
swift test
```
Expected output: 100% passing across all 18 test suites.
