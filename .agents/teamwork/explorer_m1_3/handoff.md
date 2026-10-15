# Handoff Report — Explorer 3 (UI Presentation & Session Media Retention)

**Milestone**: M1 (Audio Playback & Karaoke Sync)  
**Agent**: Explorer 3 (`explorer_m1_3`)  
**Type**: Hard Handoff (Investigation Complete)  
**Related Documents**: `m1_3_exploration.md`, `PROJECT.md`, `ORIGINAL_REQUEST.md`

---

## 1. Observation
1. **Immediate Media Deletion**:
   - In `Sources/TranskriptHubApp/ViewModels/AppViewModel.swift:981-985`:
     ```swift
     let itemWorkspace = FileManager.default.temporaryDirectory
         .appendingPathComponent("transkript_\(item.id)_\(UUID().uuidString)", isDirectory: true)
     try FileManager.default.createDirectory(at: itemWorkspace, withIntermediateDirectories: true)
     defer { try? FileManager.default.removeItem(at: itemWorkspace) }
     ```
   - In `AppViewModel.swift:1015`:
     ```swift
     let media = try await ytdlp.fetch(url: video.canonicalURL, into: itemWorkspace)
     ```
     The downloaded audio was stored in `itemWorkspace` and instantly deleted upon loop iteration completion via `defer`.
2. **Missing Properties on `QueueItem`**:
   - In `Sources/TranskriptHubApp/Models/QueueItem.swift:17-32`, `QueueItem` had:
     `public var transcript: String?`
     `public var outputURL: URL?`
     `QueueItem` had NO `audioURL: URL?`, NO `segments: [Segment]`, and NO `waveformPoints: [WaveformPoint]?`.
3. **Disposal of Whisper Segments**:
   - In `AppViewModel.swift:1066-1068`:
     ```swift
     let formatted = postProcessor.process(segments: result.segments)
     current.transcript = formatted
     ```
     `result.segments` (which holds token/word-level millisecond timestamps) was converted into plain text and never persisted in `QueueItem`.
4. **Single-View Transcript Reader in `TranscriptDetailView`**:
   - In `Sources/TranskriptHubApp/Views/TranscriptDetailView.swift:64-65`:
     ```swift
     } else if let text = transcript, !text.isEmpty {
         transcriptReader(text: text)
     }
     ```
     `transcriptReader` invokes `NativeTranscriptTextView` (AppKit `NSTextView`). There is currently no waveform visualizer, audio player controller, or interactive karaoke token view.
5. **Keyboard Shortcuts Interception in `ContentView`**:
   - In `Sources/TranskriptHubApp/Views/ContentView.swift:370-418`, `KeyInterceptingView` intercepts `⌘K`, `⌘V`, `⌘⇧C`, and `⌘A`, but does NOT intercept `Space` (play/pause toggle) or arrow keys (seek -5s/+5s).

---

## 2. Logic Chain
1. *From Observation 1*: Because `itemWorkspace` was removed by `defer`, downloaded YouTube audio files were immediately wiped from disk before the user could play them.
2. *From Observation 2 & 3*: Because `QueueItem` did not store `audioURL` or `segments: [Segment]`, even if audio remained on disk, the UI had no reference to the audio file or the word-level timestamps needed for karaoke synchronization.
3. *From Logic Steps 1 & 2*: A dedicated `SessionMediaDirectory` in `Application Support/TranskriptHub/SessionMedia/` must be introduced, where downloaded YouTube audio is retained for the active session, and `QueueItem` must be updated with `audioURL`, `segments: [Segment]`, and `waveformPoints: [WaveformPoint]?`.
4. *From Observation 4*: To satisfy R1, AC#1, and AC#2, `TranscriptDetailView` must host a two-tier studio view:
   - Upper deck: `WaveformVisualizerView` (Apple Voice Memos-style interactive waveform with click-to-seek, smooth 60/120fps scrub, and Liquid Glass transport bar).
   - Main body: `KaraokeTranscriptView` (word tokens with active glow, spring scale, and click-to-seek) with a mode switcher allowing fallback to `NativeTranscriptTextView` for plain text reading.
5. *From Performance Constraints (R6)*: Rendering 300+ individual SwiftUI `Rectangle` views on every 60Hz tick causes view diffing lag. Rendering the waveform using SwiftUI `Canvas` executes directly on Metal with zero heap allocations during playback. Scoping active word updates to only the active `Segment` row keeps CPU usage near 0%.
6. *From Observation 5*: Adding `Space` handling to `KeyInterceptingView` (with a check that `window.firstResponder` is not an editable text input) fulfills the Spacebar playback toggle requirement (AC#3).

---

## 3. Caveats
1. **Security-Scoped Bookmarks for Local Files**: Local files dragged from disk are immediately accessible for the current session. If the user quits and relaunches the app, access to external files may require standard security-scoped bookmarks or reloading from user selection.
2. **Old History Items Without Audio**: Historical transcripts imported or created in previous versions without associated audio files will not have `audioURL`. `TranscriptDetailView` must cleanly handle this by displaying a subtle "Ses Kaydı Bulunamadı (Salt Metin)" chip and defaulting to `NativeTranscriptTextView`.
3. **Whisper Word Timestamps Dependency**: Word-level highlighting relies on Explorer 1 (`explorer_m1_1`) completing the `wparams.token_timestamps = true` extraction in `WhisperCppEngine.swift`. If segments do not contain words, `KaraokeTranscriptView` gracefully falls back to segment-level time interpolation.

---

## 4. Conclusion
1. Create `Sources/TranskriptHubApp/Views/WaveformVisualizerView.swift` using SwiftUI `Canvas` for 60/120fps Metal-backed scrub and playback indicator, integrated with `AudioPlaybackControlling`.
2. Create `Sources/TranskriptHubApp/Views/KaraokeTranscriptView.swift` using `WordFlowLayout`, `LazyVStack` segment rows, active word illumination (`Color.accentColor` halo + 1.04x scale), click-to-seek, and `ScrollViewReader` auto-scroll.
3. Update `Sources/TranskriptHubApp/Models/QueueItem.swift` to add `audioURL: URL?`, `segments: [Segment]`, and `waveformPoints: [WaveformPoint]?`.
4. Update `Sources/TranskriptHubApp/ViewModels/AppViewModel.swift` to retain YouTube audio in `SessionMedia/`, store `result.segments`, generate waveform points via `WaveformGenerator`, and manage `audioPlayer: AudioPlayerController`.
5. Update `Sources/TranskriptHubApp/Views/TranscriptDetailView.swift` to embed the waveform deck and karaoke transcript view.
6. Update `Sources/TranskriptHubApp/Views/ContentView.swift` to intercept `Space` for play/pause and `⌘←`/`⌘→` for 5-second seeking.

---

## 5. Verification Method
1. **Compilation & Build**:
   ```bash
   swift build
   ```
   Must compile cleanly with zero warnings or errors.
2. **Session Media Retention Verification**:
   - Inspect `QueueItem` after completing a transcription task; verify `item.audioURL` is non-nil and points to an existing file in `SessionMedia/`.
   - Verify `item.segments.first?.words` is non-empty.
3. **Interactive Click-to-Seek Verification**:
   - In `KaraokeTranscriptView`, click a word token at timestamp `T`.
   - Verify `audioPlayer.currentTime` seeks to `T` (within ±50ms, meeting AC#1's ±100ms tolerance).
4. **Waveform Scrubbing Verification**:
   - Drag across `WaveformVisualizerView` canvas; verify playhead moves smoothly at 60/120fps without frame hitching.
5. **Keyboard Ergonomics**:
   - Press Spacebar; verify audio toggles between playing and paused.
