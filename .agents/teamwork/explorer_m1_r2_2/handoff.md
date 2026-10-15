# Handoff Report: AudioPlayerController deinit & Observer Teardown (Finding 2)

**From**: `explorer_m1_r2_2`  
**To**: `orchestrator_1` / `worker_m1_2`  
**Milestone**: Milestone 1 (Audio Playback & Karaoke Sync) — Iteration 2  
**Date**: 2026-10-15T19:51:30Z  

---

## 1. Observation

1. **Missing `deinit` in `AudioPlayerController.swift`**:
   - Location: `Sources/TranskriptHubCore/Audio/AudioPlayerController.swift` (lines 35–307).
   - In lines 64–68, `AudioPlayerController` declares:
     ```swift
     private var player: AVPlayer?
     private var timeObserverToken: Any?
     private var endObserverToken: (any NSObjectProtocol)?
     ```
   - In lines 242–273, `attachTimeObserver()` calls `player.addPeriodicTimeObserver(...)` and `attachEndObserver(for:)` calls `NotificationCenter.default.addObserver(...)`.
   - Observer cleanup is ONLY implemented in `stop()` (lines 196–205):
     ```swift
     if let player = player, let token = timeObserverToken {
         player.removeTimeObserver(token)
         timeObserverToken = nil
     }
     if let endToken = endObserverToken {
         NotificationCenter.default.removeObserver(endToken)
         endObserverToken = nil
     }
     ```
   - There is NO `deinit` implemented in the class.

2. **Verbatim Swift 6 Compiler Concurrency Diagnostics for Naive `deinit`**:
   Executing `swift -swift-version 6 -enable-experimental-feature StrictConcurrency` on a naive `deinit`:
   ```
   error: cannot access property 'timeObserverToken' with a non-Sendable type 'Any?' from nonisolated deinit
   error: cannot access property 'endObserverToken' with a non-Sendable type '(any NSObjectProtocol)?' from nonisolated deinit
   `- note: add 'isolated' to run isolated to 'MainActor', which may be later than 'nonisolated deinit'
   ```

3. **Empirical Verification of `isolated deinit`**:
   Executing `swift -swift-version 6 -enable-experimental-feature StrictConcurrency` with `isolated deinit { stop() }` compiled with exit code 0 and executed cleanly across both main thread and background thread drops (runtime scheduled teardown on `isMainThread: true`).

4. **Empirical Demonstration of NotificationCenter Leaked Closure**:
   When an observer token is discarded without `NotificationCenter.default.removeObserver`, posting the notification continues invoking the orphan block even after the weak target is nil:
   ```
   LEAKED OBSERVER CLOSURE CALLED AFTER TARGET DEALLOCATED!
   ```

5. **Current Test Status**:
   `swift test --filter AudioPlayerControllerTests` runs 9 tests in 0.038s, passing 100%.

---

## 2. Logic Chain

1. **Observation 1 & 4** show that if an `AudioPlayerController` instance is deallocated without an explicit call to `stop()`, `timeObserverToken` and `endObserverToken` are never detached. This violates AVFoundation rules and permanently leaks closure allocations in `NotificationCenter.default`.
2. **Observation 2** shows that a standard `nonisolated deinit` is rejected by the Swift 6 compiler under `-strict-concurrency=complete` because `AudioPlayerController` is an `@MainActor` class and its observer tokens (`Any?`, `(any NSObjectProtocol)?`) and `AVPlayer?` are non-Sendable types.
3. **Observation 3** shows that SE-0371 `isolated deinit` provides the language-level solution:
   - It maintains `@MainActor` isolation during object destruction.
   - It allows direct synchronous calls to the `@MainActor` `stop()` method.
   - The Swift runtime automatically handles reference drops occurring on background threads by marshaling deallocation onto the `MainActor` executor.
4. Calling `stop()` inside `isolated deinit` halts active audio playback (`player?.pause()`), removes both observer tokens idempotently, nils all references, and clears seek state.
5. Therefore, adding `isolated deinit { stop() }` completely resolves Finding 2 with 3 lines of code and zero additional wrapper types.

---

## 3. Caveats

1. **Finding 1 vs Finding 2 Synergy**: Explorer 2's focus was Finding 2 (`deinit` teardown). However, updating `stop()` to clear `inFlightSeekTime = nil` (Finding 1) directly benefits `deinit` as well by ensuring full state cleanup. The implementer should ensure both fixes harmonize.
2. **Target Platform**: SE-0371 `isolated deinit` requires Swift 6.0+ compiler and is fully supported on the project's target platform (`macOS .v14`).

---

## 4. Conclusion

1. **Recommended Implementation**:
   In `Sources/TranskriptHubCore/Audio/AudioPlayerController.swift`:
   - Add `isolated deinit { stop() }` immediately following `stop()`.
   - In `stop()`, add `inFlightSeekTime = nil` to ensure seek state is also reset during teardown.
2. **Recommended Tests**:
   In `Tests/TranskriptHubCoreTests/AudioPlayerControllerTests.swift`:
   - Add `testDeallocationCleansUpObserversWithoutStop()` verifying deallocation without `stop()` frees the instance via weak reference and unregisters from NotificationCenter.
   - Add `testDeallocationAfterExplicitStop()` verifying idempotency.
   - Add `testDeallocationWhileIdle()` verifying unloaded controller teardown.

Detailed code diffs, rationale, and full test implementations are documented in `m1_r2_2_exploration.md`.

---

## 5. Verification Method

1. **Inspect Code**:
   Confirm `isolated deinit { stop() }` is present in `AudioPlayerController.swift`.
2. **Execute Unit Tests**:
   ```bash
   swift test --filter AudioPlayerControllerTests
   ```
   Must pass with 12 tests in <0.10s, 0 compiler warnings.
3. **Execute Full Suite**:
   ```bash
   swift test
   ```
   Must compile cleanly with zero warnings and pass all test suites.
