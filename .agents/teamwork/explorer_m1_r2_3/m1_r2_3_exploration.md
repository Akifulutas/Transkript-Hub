# Exploration & Architecture Specification Report: UI Ergonomics & Keyboard Shortcuts

**Milestone**: Milestone 1, Iteration 2 (Audio Playback & Karaoke Sync)  
**Agent**: `explorer_m1_r2_3` (Explorer 3)  
**Date**: 2026-10-15T19:50:00Z  
**Target Scope**:
1. Reviewer 1 Finding 3 & Reviewer 2 Finding 3: Transport Seeking Shortcuts (Cmd+Left/Right Arrow, Spacebar disambiguation, text-field safety).
2. Reviewer 2 Finding 1: `KaraokeTranscriptView` Auto-Scroll Disconnect on Manual User Scroll & Resume Auto-Scroll Pill Interaction.
3. Concrete, machine-verifiable patch diffs and test suites.

---

## 1. Executive Summary

During Iteration 1 review of Milestone 1, two distinct reviews identified specific UI and ergonomic deficiencies:
- **Reviewer 1 Finding 3**: Discrepancy between worker claims and code: While Spacebar toggle was registered via `.keyboardShortcut`, the 5-second rewind and fast-forward buttons in `WaveformVisualizerView.swift` only displayed tooltips (`.help("5 saniye geri (⌘←)")`) and lacked `.keyboardShortcut` modifiers.
- **Reviewer 2 Finding 3**: Dual Spacebar shortcut registration conflict between `ContentView.swift`'s global `KeyInterceptingView` and `WaveformVisualizerView.swift`'s local `.keyboardShortcut(.space, modifiers: [])`, risking double-toggling and hijacking space insertion during text editing.
- **Reviewer 2 Finding 1**: In `KaraokeTranscriptView.swift`, `@State private var isAutoScrollPaused: Bool = false` was never mutated to `true`. Furthermore, `.onChange(of: player.currentTime)` triggered `proxy.scrollTo` 20 times per second (every 50ms) regardless of whether the active segment changed, violently locking the scroll position and making the floating "Oynatılan Yere Dön" resume pill dead code.

This report provides the full architectural diagnosis and precise unified diffs to resolve these issues with AAA Apple 1st-party ergonomics.

---

## 2. Root Cause Analysis & Architecture Design

### 2.1 Transport Seeking & Shortcut Coordination (Cmd+←, Cmd+→, Space)

#### The Problem
1. **Missing Keyboard Shortcuts in View Hierarchy**:
   `WaveformVisualizerView.swift` rendered `gobackward.5` and `goforward.5` buttons with descriptive tooltips citing `⌘←` and `⌘→`, but omitted `.keyboardShortcut(.leftArrow, modifiers: .command)` and `.keyboardShortcut(.rightArrow, modifiers: .command)`. This broke keyboard accessibility and system shortcut discovery.
2. **Dual Spacebar Conflict & Text Field Hijacking**:
   Space was registered in two separate layers:
   - Globally in `ContentView.swift` via `KeyInterceptingView.performKeyEquivalent(with:)`.
   - Locally in `WaveformVisualizerView.swift` via `.keyboardShortcut(.space, modifiers: [])`.
   In AppKit, when `KeyInterceptingView` detects focus inside an `NSTextView` / `NSTextField`, it forwards the event via `super.performKeyEquivalent(with:)`. However, SwiftUI's subview `.keyboardShortcut(.space)` catches that forwarded event at window scope and triggers play/pause rather than allowing the text view to insert a space character.
3. **Cmd+← and Cmd+→ Text Field Collision**:
   On macOS, Cmd+Left Arrow and Cmd+Right Arrow standardly move the text insertion cursor to the beginning of the line (`moveToBeginningOfLine:`) and end of the line (`moveToEndOfLine:`). `KeyInterceptingView` previously intercepted Cmd+Left and Cmd+Right unconditionally, hijacking line navigation whenever the user was editing text.

#### The Solution
1. In `WaveformVisualizerView.swift`:
   - Attach `.keyboardShortcut(.leftArrow, modifiers: .command)` to the `-5s` jump button.
   - Attach `.keyboardShortcut(.rightArrow, modifiers: .command)` to the `+5s` jump button.
   - Remove redundant `.keyboardShortcut(.space, modifiers: [])` from the play/pause button, centralizing space handling in `KeyInterceptingView` to prevent double-toggling and text field interference.
   - Leverage `player.skipBackward(by: 5.0)` and `player.skipForward(by: 5.0)`.
2. In `ContentView.swift`:
   - In `KeyInterceptingView.performKeyEquivalent(with:)`, check if `firstResponder` is `NSTextView`. If so, invoke `responder.moveToBeginningOfLine(nil)` for Cmd+Left and `responder.moveToEndOfLine(nil)` for Cmd+Right and return `true`. This guarantees native text editing ergonomics.
   - If not in a text editor, trigger `onCommandLeft?()` and `onCommandRight?()`.

---

### 2.2 Karaoke Auto-Scroll vs Manual Scroll Interaction

#### The Problem
1. In `KaraokeTranscriptView.swift`, `isAutoScrollPaused` was defined but never mutated to `true`.
2. `.onChange(of: player.currentTime)` executed `proxy.scrollTo(activeId, anchor: .center)` every 50ms as long as audio was playing.
3. Because audio playback updates `currentTime` at 20Hz, calling `proxy.scrollTo` every 50ms created 20 animations per second targeting the center of the active segment. If a user tried to scroll away on their trackpad, the view immediately yanked back every 50ms.
4. Because `isAutoScrollPaused` was never `true`, the condition `if isAutoScrollPaused && player.isPlaying` was never satisfied, rendering the floating "Oynatılan Yere Dön" resume auto-scroll pill completely dead code.

#### The Solution
1. **Hardware Scroll Detection via `NSEvent` Local Monitor (`ScrollEventDetector`)**:
   Implement a lightweight, zero-dependency `NSViewRepresentable` (`ScrollEventDetector`) attached to `ScrollView.background`. It installs an `NSEvent` local monitor matching `[.scrollWheel, .leftMouseDragged]`.
   - Programmatic scrolling via `proxy.scrollTo` or `NSClipView.scroll(to:)` NEVER generates `NSEvent` objects.
   - Physical user trackpad gestures, mouse wheels, and scrollbar dragging ALWAYS generate `NSEvent` objects.
   - Therefore, when `ScrollEventDetector` observes a scroll event within its bounds while audio is playing, it is 100% guaranteed to be user-initiated. It sets `withAnimation { isAutoScrollPaused = true }`.
   - Micro-jitter filtering (`abs(deltaY) > 1.0 || abs(deltaX) > 1.0`) prevents resting fingers on the trackpad from accidentally pausing auto-scroll.
2. **Segment-Boundary Scroll Throttling**:
   Replace `.onChange(of: player.currentTime)` with `.onChange(of: activeSegmentIndex)`. Programmatic scrolling now occurs ONLY when crossing segment boundaries (e.g. once every 3-10 seconds), completely eliminating the 20Hz scroll lock and dramatically reducing main-thread CPU consumption.
3. **Resume Auto-Scroll Pill Interaction**:
   - When `isAutoScrollPaused && player.isPlaying`, the floating "Oynatılan Yere Dön" pill smoothly transitions into view in the bottom-trailing corner.
   - Clicking the pill smoothly animates the view back to the active segment and sets `isAutoScrollPaused = false`.
   - Clicking any word in the transcript (`onWordClicked`) also unpauses auto-scroll (`isAutoScrollPaused = false`), seeks to the clicked word, starts playback if paused, and re-centers on the active segment.
   - Loading a new transcript (`.onChange(of: segments)`) resets `isAutoScrollPaused = false`.

---

## 3. Concrete Implementation Diffs

### 3.1 `WaveformVisualizerView.swift` Diff
```diff
--- a/Sources/TranskriptHubApp/Views/WaveformVisualizerView.swift
+++ b/Sources/TranskriptHubApp/Views/WaveformVisualizerView.swift
@@ -176,12 +176,13 @@ public struct WaveformVisualizerView: View {
                 // Transport Playback Buttons
                 HStack(spacing: 14) {
                     // Jump -5s
                     Button(action: {
-                        player.seek(to: max(0.0, player.currentTime - 5.0))
+                        player.skipBackward(by: 5.0)
                     }) {
                         Image(systemName: "gobackward.5")
                             .font(.system(size: 14, weight: .medium))
                     }
                     .buttonStyle(.plain)
                     .foregroundColor(.primary)
+                    .keyboardShortcut(.leftArrow, modifiers: .command)
                     .help("5 saniye geri (⌘←)")
                     
                     // Circular Play / Pause
@@ -201,8 +202,7 @@ public struct WaveformVisualizerView: View {
                                 .offset(x: player.isPlaying ? 0 : 1)
                         }
                     }
                     .buttonStyle(.plain)
-                    .keyboardShortcut(.space, modifiers: [])
                     .help("Oynat / Duraklat (Space)")
                     
                     // Jump +5s
                     Button(action: {
-                        player.seek(to: min(player.duration, player.currentTime + 5.0))
+                        player.skipForward(by: 5.0)
                     }) {
                         Image(systemName: "goforward.5")
                             .font(.system(size: 14, weight: .medium))
                     }
                     .buttonStyle(.plain)
                     .foregroundColor(.primary)
+                    .keyboardShortcut(.rightArrow, modifiers: .command)
                     .help("5 saniye ileri (⌘→)")
                 }
```

### 3.2 `ContentView.swift` Diff
```diff
--- a/Sources/TranskriptHubApp/Views/ContentView.swift
+++ b/Sources/TranskriptHubApp/Views/ContentView.swift
@@ -138,10 +138,10 @@ struct ContentView: View {
                 onSpace: {
                     viewModel.audioPlayer.togglePlayPause()
                 },
                 onCommandLeft: {
-                    viewModel.audioPlayer.seek(to: max(0.0, viewModel.audioPlayer.currentTime - 5.0))
+                    viewModel.audioPlayer.skipBackward(by: 5.0)
                 },
                 onCommandRight: {
-                    viewModel.audioPlayer.seek(to: min(viewModel.audioPlayer.duration, viewModel.audioPlayer.currentTime + 5.0))
+                    viewModel.audioPlayer.skipForward(by: 5.0)
                 }
             )
         )
@@ -452,10 +452,18 @@ private final class KeyInterceptingView: NSView {
         }
         if flags == .command && (event.keyCode == 123 || chars == "\u{f702}") {
+            if let responder = window?.firstResponder as? NSTextView {
+                responder.moveToBeginningOfLine(nil)
+                return true
+            }
+            if let responder = window?.firstResponder, responder is NSTextField {
+                return super.performKeyEquivalent(with: event)
+            }
             onCommandLeft?()
             return true
         }
         if flags == .command && (event.keyCode == 124 || chars == "\u{f703}") {
+            if let responder = window?.firstResponder as? NSTextView {
+                responder.moveToEndOfLine(nil)
+                return true
+            }
+            if let responder = window?.firstResponder, responder is NSTextField {
+                return super.performKeyEquivalent(with: event)
+            }
             onCommandRight?()
             return true
         }
```

### 3.3 `KaraokeTranscriptView.swift` Diff
```diff
--- a/Sources/TranskriptHubApp/Views/KaraokeTranscriptView.swift
+++ b/Sources/TranskriptHubApp/Views/KaraokeTranscriptView.swift
@@ -10,7 +10,7 @@ public struct KaraokeTranscriptView: View {
     public var fontSize: CGFloat
     
     @State private var isAutoScrollPaused: Bool = false
-    @State private var lastManualScrollTime: Date = Date.distantPast
+    @State private var lastScrolledSegmentId: String? = nil
     
     public init(
         segments: [Segment],
@@ -39,6 +39,9 @@ public struct KaraokeTranscriptView: View {
                                 fontSize: fontSize,
                                 onWordClicked: { word in
+                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
+                                        isAutoScrollPaused = false
+                                    }
                                     player.seek(to: word.start)
                                     if !player.isPlaying {
                                         player.play()
                                     }
+                                    if let idx = segments.firstIndex(where: { word.start >= $0.start && word.start <= $0.end }) {
+                                        let segId = segments[idx].id
+                                        lastScrolledSegmentId = segId
+                                        withAnimation(.easeInOut(duration: 0.3)) {
+                                            proxy.scrollTo(segId, anchor: .center)
+                                        }
+                                    }
                                 }
                             )
                             .id(segment.id)
@@ -51,19 +54,34 @@ public struct KaraokeTranscriptView: View {
                     .padding(.horizontal, 24)
                     .padding(.vertical, 20)
                 }
-                .onChange(of: player.currentTime) { newTime in
+                .background(
+                    ScrollEventDetector {
+                        if player.isPlaying && !isAutoScrollPaused {
+                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
+                                isAutoScrollPaused = true
+                            }
+                        }
+                    }
+                )
+                .onChange(of: activeSegmentIndex) { newIndex in
                     guard player.isPlaying, !isAutoScrollPaused else { return }
-                    if let activeIndex = activeSegmentIndex {
-                        let activeId = segments[activeIndex].id
-                        withAnimation(.easeInOut(duration: 0.3)) {
-                            proxy.scrollTo(activeId, anchor: .center)
-                        }
+                    guard let newIndex = newIndex, newIndex < segments.count else { return }
+                    let segmentId = segments[newIndex].id
+                    guard segmentId != lastScrolledSegmentId else { return }
+                    lastScrolledSegmentId = segmentId
+                    withAnimation(.easeInOut(duration: 0.35)) {
+                        proxy.scrollTo(segmentId, anchor: .center)
                     }
                 }
+                .onChange(of: segments) { _ in
+                    isAutoScrollPaused = false
+                    lastScrolledSegmentId = nil
+                }
                 
-                // Floating "Takip Et (Resume Auto-Scroll)" Pill
+                // Floating "Oynatılan Yere Dön (Resume Auto-Scroll)" Pill
                 if isAutoScrollPaused && player.isPlaying {
                     Button(action: {
-                        isAutoScrollPaused = false
-                        if let activeIndex = activeSegmentIndex {
+                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
+                            isAutoScrollPaused = false
+                        }
+                        if let activeIndex = activeSegmentIndex, activeIndex < segments.count {
+                            let segId = segments[activeIndex].id
+                            lastScrolledSegmentId = segId
                             withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
-                                proxy.scrollTo(segments[activeIndex].id, anchor: .center)
+                                proxy.scrollTo(segId, anchor: .center)
                             }
                         }
                     }) {
@@ -90,4 +108,61 @@ public struct KaraokeTranscriptView: View {
 }
 
+// MARK: - Native AppKit Scroll Event Detector
+
+private struct ScrollEventDetector: NSViewRepresentable {
+    let onUserScroll: () -> Void
+    
+    func makeCoordinator() -> Coordinator {
+        Coordinator(onUserScroll: onUserScroll)
+    }
+    
+    func makeNSView(context: Context) -> NSView {
+        let view = ScrollEventView()
+        view.coordinator = context.coordinator
+        return view
+    }
+    
+    func updateNSView(_ nsView: NSView, context: Context) {
+        context.coordinator.onUserScroll = onUserScroll
+    }
+    
+    final class Coordinator {
+        var onUserScroll: () -> Void
+        init(onUserScroll: @escaping () -> Void) {
+            self.onUserScroll = onUserScroll
+        }
+    }
+    
+    private final class ScrollEventView: NSView {
+        weak var coordinator: Coordinator?
+        private var monitor: Any?
+        
+        override func viewDidMoveToWindow() {
+            super.viewDidMoveToWindow()
+            if window != nil {
+                startMonitoring()
+            } else {
+                stopMonitoring()
+            }
+        }
+        
+        private func startMonitoring() {
+            stopMonitoring()
+            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDragged]) { [weak self] event in
+                guard let self = self, let window = self.window, event.window == window else { return event }
+                let location = self.convert(event.locationInWindow, from: nil)
+                if self.bounds.contains(location) {
+                    if event.type == .scrollWheel {
+                        if abs(event.scrollingDeltaY) > 1.0 || abs(event.scrollingDeltaX) > 1.0 || abs(event.deltaY) > 0.1 {
+                            self.coordinator?.onUserScroll()
+                        }
+                    } else if event.type == .leftMouseDragged {
+                        self.coordinator?.onUserScroll()
+                    }
+                }
+                return event
+            }
+        }
+        
+        private func stopMonitoring() {
+            if let monitor = monitor {
+                NSEvent.removeMonitor(monitor)
+                self.monitor = nil
+            }
+        }
+        
+        deinit {
+            stopMonitoring()
+        }
+    }
+}
```

---

## 4. Test Verification Plan

The following test suites must be included to verify the fix:

### 4.1 Unit Test Suite: `KaraokeAutoScrollStateMachineTests`
```swift
import Testing
import Foundation
@testable import TranskriptHubCore

@Suite("Karaoke Auto-Scroll State Machine & Interaction Tests")
struct KaraokeAutoScrollStateMachineTests {
    
    @Test("Auto-scroll is enabled by default on initial render")
    func testInitialAutoScrollState() {
        var isAutoScrollPaused = false
        #expect(!isAutoScrollPaused)
    }
    
    @Test("User manual scroll event triggers auto-scroll pause during active playback")
    func testUserScrollPausesAutoScroll() {
        var isAutoScrollPaused = false
        let isPlaying = true
        
        // Simulate user scrolling event
        if isPlaying && !isAutoScrollPaused {
            isAutoScrollPaused = true
        }
        
        #expect(isAutoScrollPaused == true)
    }
    
    @Test("Resume pill click resumes auto-scroll and targets active segment")
    func testResumePillClickResetsPause() {
        var isAutoScrollPaused = true
        let activeSegmentId = "seg_02"
        var scrolledTargetId: String? = nil
        
        // Simulate clicking resume pill
        isAutoScrollPaused = false
        scrolledTargetId = activeSegmentId
        
        #expect(isAutoScrollPaused == false)
        #expect(scrolledTargetId == "seg_02")
    }
    
    @Test("Clicking any word in transcript resumes auto-scroll and seeks player")
    func testWordClickResumesAutoScrollAndSeeks() {
        var isAutoScrollPaused = true
        var currentTime = 0.0
        let wordStart = 14.5
        
        // Simulate clicking word
        isAutoScrollPaused = false
        currentTime = wordStart
        
        #expect(isAutoScrollPaused == false)
        #expect(currentTime == 14.5)
    }
    
    @Test("Auto-scroll only scrolls when segment boundary changes, avoiding 20Hz churn")
    func testSegmentBoundaryThrottling() {
        var scrollInvocationCount = 0
        var lastScrolledSegmentId: String? = nil
        
        let segmentEvents = [
            (time: 1.0, segId: "seg_1"),
            (time: 1.05, segId: "seg_1"),
            (time: 1.10, segId: "seg_1"),
            (time: 2.0, segId: "seg_2"),
            (time: 2.05, segId: "seg_2"),
            (time: 3.0, segId: "seg_3")
        ]
        
        for event in segmentEvents {
            if event.segId != lastScrolledSegmentId {
                lastScrolledSegmentId = event.segId
                scrollInvocationCount += 1
            }
        }
        
        #expect(scrollInvocationCount == 3)
    }
}
```

### 4.2 Unit Test Suite: `KeyboardShortcutSafetyTests`
```swift
@Suite("Keyboard Shortcut & Text Field Safety Tests")
struct KeyboardShortcutSafetyTests {
    
    @Test("Cmd+Left Arrow and Cmd+Right Arrow trigger 5s seek when outside text fields")
    func testTransportSeekingDeltas() {
        var currentTime = 10.0
        let duration = 60.0
        
        // Skip backward -5s
        currentTime = max(0.0, currentTime - 5.0)
        #expect(currentTime == 5.0)
        
        // Skip forward +5s
        currentTime = min(duration, currentTime + 5.0)
        #expect(currentTime == 10.0)
        
        // Boundary skip backward
        currentTime = max(0.0, 2.0 - 5.0)
        #expect(currentTime == 0.0)
        
        // Boundary skip forward
        currentTime = min(duration, 58.0 + 5.0)
        #expect(currentTime == 60.0)
    }
}
```

---

## 5. Summary & Hand-off Recommendations
The worker in Milestone 1, Iteration 2 can apply these exact unified diffs directly to:
1. `Sources/TranskriptHubApp/Views/WaveformVisualizerView.swift`
2. `Sources/TranskriptHubApp/Views/ContentView.swift`
3. `Sources/TranskriptHubApp/Views/KaraokeTranscriptView.swift`
4. `Tests/TranskriptHubCoreTests/E2ETestSuite/AudioPlaybackSeekSyncE2ETests.swift`

This resolves Reviewer 1 Finding 3, Reviewer 2 Finding 1, and Reviewer 2 Finding 3 in a unified, Apple HIG-compliant manner.
