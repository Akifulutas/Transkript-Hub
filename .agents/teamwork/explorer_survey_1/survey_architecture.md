# Architecture & Codebase Survey Report: Transkript Hub

**Author:** Explorer 1 (Teamwork Explorer)  
**Date:** 2026-10-15  
**Working Directory:** `/Users/akifulutas/Documents/Akif/Transkript Hub.txt/.agents/teamwork/explorer_survey_1`  
**Target Project:** Transkript Hub (`/Users/akifulutas/Documents/Akif/Transkript Hub.txt`)

---

## 1. Executive Summary

Transkript Hub is a native macOS 14+ (Sonoma/Sequoia) Apple Silicon audio and video transcription studio. It relies on a high-performance C/C++ `whisper.cpp` binary runtime (`whisper.xcframework`) running on the Metal GPU, wrapped in a pure Swift core library (`TranskriptHubCore`), backed by SQLite persistence via `GRDB.swift`, and surfaced through a SwiftUI 6 + AppKit desktop application (`TranskriptHubApp`) and command-line tool (`transkripthub-cli`).

### Verification Snapshot
- **Build Status:** `swift build` compiles cleanly with zero warnings or errors in ~0.37 seconds.
- **Test Suite:** `swift test` runs 39 tests (36 Swift Testing `@Test` across 7 suites + 3 XCTest cases) in ~0.05 seconds with 100% pass rate.
- **Distribution Size:** Packaged DMG (`dist/TranskriptHub.dmg`) is **7.4 MB** (well under the <10 MB / 15 MB mandate).
- **External Dependency Footprint:** Exactly 1 Swift package (`GRDB.swift` 7.0.0+) and 1 local C/C++ binary framework (`whisper.xcframework`). Zero Python, zero FFmpeg, zero Homebrew.

---

## 2. Source Code Tree & Package Layout

```
Transkript Hub.txt/
├── Package.swift                    # Swift 6 package manifest (macOS 14+, StrictConcurrency)
├── Package.resolved                 # Resolved GRDB.swift dependency
├── Frameworks/
│   └── whisper.xcframework/        # Multiplatform xcframework (macOS slice is 5.9MB)
│       └── macos-arm64_x86_64/
│           └── whisper.framework/   # Headers (whisper.h, ggml.h, etc.) & binary
├── Resources/
│   ├── AppIcon.icns                # Application icon
│   ├── PrivacyInfo.xcprivacy       # Privacy declaration
│   └── TranskriptHub.entitlements  # Network client, user-selected files, JIT/hardened runtime
├── scripts/
│   └── package_dmg.sh              # Release build, code sign, and UDZO DMG creator
├── Sources/
│   ├── TranskriptHubCore/          # Pure Swift Core Library (Zero UI imports)
│   │   ├── Audio/
│   │   │   ├── AudioDecoder.swift    # AVFoundation 16kHz mono Float32 PCM conversion
│   │   │   ├── AudioValidator.swift  # Format, duration (>=1s), and file size verification
│   │   │   └── PreparedAudio.swift   # [Float] sample buffer & duration container
│   │   ├── Transcription/
│   │   │   ├── TranscriptionModels.swift # Segment, TranscriptResult, TranscriptionOptions
│   │   │   ├── TranscriptionEngine.swift # Protocol abstraction
│   │   │   ├── WhisperCppEngine.swift    # Metal GPU whisper_full bridge & callbacks
│   │   │   ├── WhisperModelCatalog.swift # Catalog of available Whisper models
│   │   │   ├── ModelManager.swift        # HuggingFace model download & SHA256 validation
│   │   │   └── TranscriptPostProcessor.swift # Tag cleansing, repetition break, paragraphs
│   │   ├── Database/
│   │   │   ├── AppDatabase.swift     # GRDB DatabaseQueue & migrations (v1, v2)
│   │   │   └── DatabaseModels.swift  # BatchRecord, JobRecord, TranscriptSectionRecord
│   │   ├── Jobs/
│   │   │   └── JobManager.swift      # Actor orchestrating batch execution & crash recovery
│   │   ├── Batch/
│   │   │   ├── BatchAssembler.swift  # Multi-job assembly & 22/25 resilient partial assembly
│   │   │   └── OutputFormatter.swift # Format-Version 1 header & markdown text structure
│   │   ├── Output/
│   │   │   └── OutputWriter.swift    # Atomic .partial writing, sanitization, (2) collision handling
│   │   ├── Cache/
│   │   │   └── TranscriptCacheManager.swift # Smart deduplication (duration +-1s & title)
│   │   ├── Cleanup/
│   │   │   └── CleanupManager.swift  # Workspace cleanup & temp audio purging
│   │   ├── Sources/
│   │   │   ├── URLParser.swift       # Robust URLComponents YouTube parser
│   │   │   ├── YouTubeMetadataResolver.swift # Lightweight oEmbed metadata resolver
│   │   │   └── FolderWatcher.swift   # FSEvent directory & iCloud Drive .icloud monitoring
│   │   ├── Tools/
│   │   │   ├── ToolManager.swift     # Standalone yt-dlp & Deno downloader & runner
│   │   │   └── YTDLPClient.swift     # Process execution & download progress parser
│   │   ├── System/
│   │   │   └── ClipboardMonitor.swift# NSPasteboard 0.75s polling, ignores password managers
│   │   ├── Permissions/
│   │   │   └── FullDiskAccessHelper.swift # TCC / Voice Memos permission inspection
│   │   ├── Logging/
│   │   │   └── Log.swift             # OSLog wrapper
│   │   └── Updates/
│   │       └── UpdateChecker.swift   # Sparkle / GitHub releases checker
│   ├── TranskriptHubApp/           # macOS GUI Application Target (SwiftUI 6 + AppKit)
│   │   ├── TranskriptHubApp.swift    # @main App, WindowGroup, MenuBarExtra, AppDelegate
│   │   ├── ViewModels/
│   │   │   └── AppViewModel.swift    # MainActor ObservableObject (queue, states, jobs)
│   │   ├── Models/
│   │   │   └── QueueItem.swift       # QueueItem, QueueItemState, HistoryItem
│   │   ├── DesignSystem/
│   │   │   ├── LiquidGlass.swift     # LiquidGlassCardModifier, LiquidGlassCapsuleModifier
│   │   │   └── VisualEffectView.swift# NSVisualEffectView & WindowAccessor
│   │   ├── Localization/
│   │   │   └── AppLanguage.swift     # English, German, Turkish localization dictionary
│   │   └── Views/
│   │       ├── ContentView.swift             # Root 2-column NavigationSplitView & modals
│   │       ├── SidebarView.swift             # Standard macOS sidebar (currently orphaned)
│   │       ├── QueueListView.swift           # Grouped queue (Failed, Processing, Done)
│   │       ├── TranscriptDetailView.swift    # Inspector header, live view, reader
│   │       ├── NativeTranscriptTextView.swift# NSViewRepresentable uneditable NSTextView
│   │       ├── HistoryListView.swift         # Searchable completed transcripts archive
│   │       ├── WatchedFolderView.swift       # iCloud & Voice Memos monitoring settings
│   │       ├── SettingsView.swift            # Models, storage, automation settings
│   │       ├── MenuBarMiniWindow.swift       # Quick status popover & link input
│   │       ├── PlaylistIngestionSheet.swift  # Multi-link playlist selection modal
│   │       ├── SessionSaveModeSheet.swift    # Combined vs. Individual export modal
│   │       └── FloatingSettingsSheet.swift   # Sheet wrapper for settings
│   └── transkripthub-cli/
│       └── main.swift                # CLI utility for batch, youtube, transcribe, tools
└── Tests/
    └── TranskriptHubCoreTests/       # 39 passing unit & integration tests
```

---

## 3. Package Dependencies & Build Configuration

From `Package.swift`:
```swift
// swift-tools-version: 6.0
platforms: [.macOS(.v14)]
dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
]
targets: [
    .binaryTarget(name: "whisper", path: "Frameworks/whisper.xcframework"),
    .target(name: "TranskriptHubCore", dependencies: ["whisper", .product(name: "GRDB", package: "GRDB.swift")]),
    .executableTarget(name: "TranskriptHubApp", dependencies: ["TranskriptHubCore"]),
    .executableTarget(name: "transkripthub-cli", dependencies: ["TranskriptHubCore"]),
    .testTarget(name: "TranskriptHubCoreTests", dependencies: ["TranskriptHubCore"])
]
```

### Key Observations:
1. **Swift 6 Strict Concurrency:** All targets enable `.enableExperimentalFeature("StrictConcurrency")`. Types crossing actor boundaries are marked `Sendable`.
2. **Apple Native Exclusivity:** Zero third-party frameworks for audio or networking. Audio decoding is AVFoundation; SQLite is GRDB; Whisper is whisper.xcframework.
3. **Distribution Size:** The entire DMG distribution is 7.4 MB. The macOS slice of `whisper.framework` is 5.9 MB. The core app binary is ~3.5 MB uncompressed.

---

## 4. Audio Pipeline: Ingestion, Processing & Transcription

```
[ Sources ]
  - YouTube Link (yt-dlp -> M4A)
  - Local Audio File (Open Panel / Drop)
  - Watched Folder / iCloud (.icloud -> download -> M4A/WAV)
  - Voice Memos (Group Container)
        │
        ▼
[ AudioValidator.swift ]
  - Checks: size > 0, tracks present, sampleRate > 0, duration >= 1.0s
        │
        ▼
[ AudioDecoder.swift ]
  - Reads input using AVAudioFile
  - Converts arbitrary container/samplerate to 16 kHz mono Float32 PCM via AVAudioConverter
  - Outputs PreparedAudio(samples: [Float], duration: Double)
        │
        ▼
[ WhisperCppEngine.swift ]
  - Metal GPU context initialized via whisper_init_from_file_with_params
  - Greedy sampling via whisper_full
  - Live progress callback -> UI progress bar
  - Live segment callback -> UI live streaming preview
        │
        ▼
[ TranscriptPostProcessor.swift ]
  - Cleans noise tags ([BLANK_AUDIO], [Music], etc.)
  - Breaks hallucination loops (>= 3 consecutive repeats)
  - Paragraph formatting based on >= 2.5s silence or ~650 char sentence boundary
        │
        ▼
[ OutputWriter.swift & TranscriptCacheManager.swift ]
  - Writes atomic Title.txt (with (2), (3) collision resolution)
  - Saves to SQLite transcript_cache for instant deduplication
```

---

## 5. Data Models & State Management

### Core Data Models (`Sources/TranskriptHubCore/Transcription/TranscriptionModels.swift`)
```swift
public struct Segment: Sendable, Codable, Equatable {
    public let start: Double // seconds
    public let end: Double   // seconds
    public let text: String
}

public struct TranscriptResult: Sendable, Codable, Equatable {
    public let segments: [Segment]
    public let detectedLanguage: String?
    public var fullText: String { ... }
}
```

### SQLite Database Records (`Sources/TranskriptHubCore/Database/DatabaseModels.swift`)
1. **`BatchRecord`**: Tracks batch lifecycle (`active`, `assembling`, `completed`, `completedWithErrors`, `cancelled`).
2. **`JobRecord`**: Tracks individual video/file job lifecycle (`queued`, `fetching`, `fetched`, `transcribing`, `transcribed`, `completed`, `failed`, `cancelled`).
3. **`TranscriptSectionRecord`**: Stores `job_id`, post-processed `text`, and nullable `segments` (JSON string).
4. **`CachedTranscript`**: Stores cached items for instant deduplication by duration ($\pm1.0$s) and title/external ID.

### UI App State (`Sources/TranskriptHubApp/Models/QueueItem.swift` & `AppViewModel.swift`)
```swift
public struct QueueItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: QueueItemKind // .youtube(ParsedYouTubeVideo) or .audioFile(URL)
    public var title: String
    public var subtitle: String
    public var durationSec: Double?
    public var state: QueueItemState // .queued, .fetching, .transcribing, .completed, .failed
    public var progress: Double
    public var transcript: String?
    public var outputURL: URL?
    public var errorMessage: String?
    public var isNewlyDiscovered: Bool
    public let addedAt: Date
    public var thumbnailURL: URL?
    public var channelTitle: String?
}
```

---

## 6. UI Views, Navigation & Window Structure

- **`TranskriptHubApp.swift`**:
  - `WindowGroup`: Standard macOS window containing `ContentView`.
  - `MenuBarExtra("Transkript Hub", ...)`: Window-style menu bar popover containing `MenuBarMiniWindow`.
  - `AppDelegate`: Configures transparent title bar, sets `applicationShouldTerminateAfterLastWindowClosed` to `false` (keeps running in menu bar).
- **`ContentView.swift`**:
  - Currently implements a **2-column** `NavigationSplitView`:
    - Column 1 (Master): Swapped between `QueueListView`, `HistoryListView`, `WatchedFolderView`, `SettingsView`.
    - Column 2 (Detail): `TranscriptDetailView`.
  - Overlays: Floating 5-second Undo Toast capsule, ⌘K Command Palette sheet, playlist and session save modals.
- **`SidebarView.swift`**:
  - Exists as a standalone component with Section items (Queue, History, Watched Folder, Settings) and bottom live status capsule, but is **currently unused** in `ContentView.swift`.
- **`NativeTranscriptTextView.swift`**:
  - Wraps `NSTextView` in `NSViewRepresentable`.
  - **Currently hardcoded as read-only (`textView.isEditable = false`).**
  - Handles search query yellow background highlighting and autoscrolling.

---

## 7. Comprehensive Gap Analysis vs Requirements R1–R6

| Req | Name | Current Implementation Status | Gap & Required Implementation |
|---|---|---|---|
| **R1** | **Native Interactive Waveform & Karaoke Player** | 🔴 **0% implemented**<br>No audio player exists in the app. No waveform generator. `QueueItem` discards segments after post-processing, retaining only a plain `transcript: String?`. | 1. Extract token timestamps from `whisper.cpp` (`wparams.token_timestamps = true`, `whisper_full_get_token_data`).<br>2. Add `Word` data model (`text`, `start`, `end`, `p`) and integrate into `Segment`.<br>3. Store `segments: [Segment]` and `audioFileURL: URL?` on `QueueItem`.<br>4. Implement `AudioPlayerController` (AVFoundation `AVPlayer` / `AVAudioPlayer`) with millisecond seeking, time observers, play/pause.<br>5. Implement Accelerate/vDSP waveform peak extractor and SwiftUI interactive scrubbing visualizer.<br>6. Implement karaoke word illumination and click-to-seek (±100ms accuracy). |
| **R2** | **In-App Audio & Microphone Recording Engine** | 🔴 **0% implemented**<br>Zero recording code. Entitlements do not contain audio input permissions. | 1. Implement `AudioRecordingEngine` using `AVAudioEngine` / `AVAudioRecorder`.<br>2. Real-time audio metering tap feeding a dynamic frequency bar visualizer.<br>3. Save recording as uncompressed WAV/M4A to temporary/export storage.<br>4. Seamless one-click auto-transcribe upon stop with queue/history entry.<br>5. Add `NSMicrophoneUsageDescription` and `com.apple.security.device.audio-input` entitlement. |
| **R3** | **Speaker Diarization & Inline Rich Editor** | 🔴 **0% implemented**<br>`Segment` lacks speaker info. `NativeTranscriptTextView` has `isEditable = false`. | 1. Add `speaker: String?` / `speakerId: Int?` to `Segment`.<br>2. Implement speaker turn clustering / diarization heuristic (turn segmentation based on silence thresholds, voice pitch, or speaker badges).<br>3. Implement Apple-style colored speaker badges ("Speaker 1", "Speaker 2") with inline renaming.<br>4. Make `NativeTranscriptTextView` or SwiftUI editor natively editable, synchronizing edits back to the model atomically.<br>5. Local summary, bullet-point action items, and timestamped chaptering generator. |
| **R4** | **Menu Bar Companion & Floating Drop-Zone** | 🟡 **30% implemented**<br>`MenuBarExtra` and `MenuBarMiniWindow` exist with link input and clipboard button. | 1. Add floating drag-and-drop zone in `MenuBarMiniWindow` accepting audio/video files and URLs.<br>2. Add quick-record toggle or global hotkey for instant dictation/recording. |
| **R5** | **macOS Sequoia Integration & Apple HIG Elegance** | 🟡 **50% implemented**<br>Liquid Glass styling, ⌘K command palette, and ⌘V exist. | 1. Restore the 3-column unified split view using `SidebarView.swift`.<br>2. Implement Spacebar play/pause shortcut.<br>3. Implement ⌘F interactive search with next/previous hit navigation.<br>4. Implement ⌘E instant multi-format export (TXT, SRT, VTT, MD).<br>5. Quick Look preview support. |
| **R6** | **Performance & Zero-Dependency Mandate** | 🟢 **100% compliant**<br>Strict Swift 6, zero extra packages, DMG 7.4 MB (<10 MB), 39 tests passing, clean build. | Ensure all new audio playback, waveform, and recording features strictly use Apple native frameworks (AVFoundation, Accelerate, AppKit, SwiftUI). Keep DMG < 15 MB. |

---

## 8. Concrete Architecture Recommendations for Implementation

1. **Audio Engine Architecture:**
   - Create `TranskriptHubCore/Audio/AudioPlayerController.swift` (actor or `@MainActor` class wrapping `AVPlayer` with `addPeriodicTimeObserver`).
   - Create `TranskriptHubCore/Audio/WaveformExtractor.swift` using `vDSP_vmaxmg` / `vDSP_desamp` in Accelerate to generate downsampled amplitude data (e.g. 100–300 normalized points) in < 15ms without blocking the main thread.
   - Create `TranskriptHubCore/Audio/AudioRecordingEngine.swift` wrapping `AVAudioEngine` with an input tap that calculates RMS / peak power for live visual metering and writes to a 16kHz WAV or M4A file.

2. **Model Enhancements:**
   - Update `TranscriptionModels.swift`:
     ```swift
     public struct Word: Sendable, Codable, Equatable, Identifiable {
         public var id: String { "\(start)-\(end)-\(text)" }
         public let text: String
         public let start: Double // seconds
         public let end: Double   // seconds
         public let probability: Float
     }
     
     public struct Segment: Sendable, Codable, Equatable, Identifiable {
         public var id: String { "\(start)-\(end)" }
         public let start: Double
         public let end: Double
         public var text: String
         public var words: [Word]
         public var speaker: String?
     }
     ```
   - In `WhisperCppEngine.swift`, enable `wparams.token_timestamps = true` and read `whisper_full_n_tokens` + `whisper_full_get_token_data` to populate `Word` objects.
   - In `QueueItem.swift`, store `segments: [Segment]?` and `audioURL: URL?`.

3. **UI & Editor Enhancements:**
   - Build `TranscriptKaraokeView` / `SynchronizedTranscriptEditor`:
     - Renders speaker turn headers with colored badges.
     - Renders words with real-time active glow/highlight when `player.currentTime >= word.start && player.currentTime <= word.end`.
     - Clicking any word dispatches `player.seek(to: word.start)`.
     - Clicking "Edit" or inline text field enables instant editing, updating `segment.text` and saving back to disk/database.
   - Embed `WaveformVisualizerView` in `TranscriptDetailView` above the transcript reader.
   - Re-introduce `SidebarView` into `ContentView` to complete the 3-column macOS desktop navigation.
