# Project: Transkript Hub — macOS Native Transcription Powerhouse

## Architecture
Transkript Hub is an ultra-lean, high-performance macOS native transcription application built with Swift 6 Concurrency and Apple native frameworks (`AVFoundation`, `Accelerate/vDSP`, `AppKit`, `SwiftUI`, `NaturalLanguage`, `CryptoKit`, `OSLog`, `GRDB.swift`, `whisper.xcframework`).

### Package & Module Boundaries
- `TranskriptHubCore`: Core library containing audio decoding, whisper.cpp C/Metal GPU engine integration, Accelerate signal processing, SQLite database persistence via GRDB, output formatters, and audio recording.
- `TranskriptHubApp`: Native macOS AppKit/SwiftUI interface with Liquid Glass vibrancy, karaoke waveform playback, inline transcript editing, menu bar companion, and keyboard ergonomics.
- `transkripthub-cli`: Headless CLI runner for offline batch transcription and pipelines.
- `TranskriptHubCoreTests`: Automated unit and integration test suite executing under XCTest and Swift Testing.

## Feature Inventory
| # | Feature ID | Feature | Description | Milestone | Source |
|---|---|---|---|---|---|
| 1 | FEAT-R1-01 | Token Timestamps Extraction | Extract word/token-level millisecond timestamps in `WhisperCppEngine` using `wparams.token_timestamps = true` and `whisper_full_get_token_data`. | M1 | R1.1, Survey |
| 2 | FEAT-R1-02 | Native Audio Player Controller | Implement `AudioPlayerController` with AVFoundation, click-to-seek (±100ms accuracy), playback status, and continuous time updates. | M1 | R1.1, AC#1, Survey |
| 3 | FEAT-R1-03 | Accelerate/vDSP Waveform Generator | Downsample audio samples into normalized amplitude envelope bars (<15ms processing) via vDSP. | M1 | R1.2, R6.2, Survey |
| 4 | FEAT-R1-04 | Interactive Waveform Visualizer | Apple Voice Memos-style interactive waveform with click-to-seek and smooth 60/120fps scrubbing. | M1 | R1.2, AC#2, Survey |
| 5 | FEAT-R1-05 | Karaoke Synchronized Transcript | Karaoke-style active word highlighting as audio plays; clicking any word jumps audio playback directly to that millisecond. | M1 | R1.3, AC#1, Survey |
| 6 | FEAT-R1-06 | Audio Session Media Retention | Retain downloaded YouTube audio and imported media in session storage for continuous playback. | M1 | R1.1, Caveats, Survey |
| 7 | FEAT-R2-01 | Audio & Mic Recording Engine | Direct in-app microphone recording engine powered by `AVAudioEngine` input node tap, saving AAC/LPCM m4a audio. | M2 | R2.1, AC#4, Survey |
| 8 | FEAT-R2-02 | Real-Time Audio Level Metering | Real-time RMS volume metering and vDSP frequency band analyzer during recording. | M2 | R2.2, AC#5, Survey |
| 9 | FEAT-R2-03 | Live Frequency Bar Visualizer | Animated live audio meter / frequency bar visualizer (`LiveAudioMeterView`) responding in real time to input volume. | M2 | R2.2, AC#5, Survey |
| 10 | FEAT-R2-04 | Instant Auto-Transcribe & Auto-Save | Instant one-click transcription upon recording stop, with auto-save to queue, history database, and user export folder. | M2 | R2.3, AC#4, Survey |
| 11 | FEAT-R2-05 | Recording Entitlements & Privacy | Microphone hardware entitlement (`com.apple.security.device.audio-input`) and `NSMicrophoneUsageDescription` in Info.plist. | M2 | R2.1, Caveats, Survey |
| 12 | FEAT-R3-01 | Acoustic Turn Diarization | Speaker turn segmentation and silence boundary clustering via vDSP energy/pause profiling. | M3 | R3.1, AC#6, Survey |
| 13 | FEAT-R3-02 | Colored Speaker Badges & Rename | Distinct Apple-style colored badges (Speaker 1, Speaker 2, ...) with inline custom speaker renaming. | M3 | R3.1, AC#6, Survey |
| 14 | FEAT-R3-03 | Inline Rich Transcript Editor | Native inline editable transcript text view allowing terms and typos to be corrected directly in place. | M3 | R3.2, AC#7, Survey |
| 15 | FEAT-R3-04 | Atomic Database Model Sync | Editing transcript text updates the underlying GRDB SQLite database model atomically. | M3 | R3.2, AC#7, Survey |
| 16 | FEAT-R3-05 | Local Summary & Chaptering | Local bullet-point action items, extractive summary, and timestamped chaptering using Apple `NaturalLanguage`. | M3 | R3.3, Survey |
| 17 | FEAT-R4-01 | Menu Bar Drag-and-Drop Extra | Menu Bar companion (`NSStatusItem` / `MenuBarExtra`) accepting drag-and-drop audio files and YouTube URLs. | M4 | R4.1, Survey |
| 18 | FEAT-R4-02 | Floating Drop-Zone & Quick Dictation | Floating drop-zone widget and quick-record dictation toggle for instantaneous audio ingestion. | M4 | R4.2, Survey |
| 19 | FEAT-R5-01 | macOS Sequoia Liquid Glass & 3-Column HIG | Apple Liquid Glass design language, `NSVisualEffectView` vibrancy, SF Symbols 6, and 3-column split view navigation using `SidebarView`. | M5 | R5.1, Survey |
| 20 | FEAT-R5-02 | Shortcuts & Quick Look Previews | Native keyboard shortcuts (⌘K Command Palette, Space play/pause, ⌘F search with hit navigation, ⌘E export) and Quick Look preview integration. | M5 | R5.2, R5.3, AC#3, Survey |
| 21 | FEAT-R6-01 | Extreme Performance & Lean Binary | Zero third-party dependencies, <10MB DMG distribution, Accelerate/vDSP optimization, launch time <200ms. | M6 | R6.1, R6.3, AC#8, AC#9, Survey |
| 22 | FEAT-R6-02 | Zero-Regression Suite Pass | 100% pass rate on all 39 existing unit/integration tests without regressions, zero Swift 6 warnings, clean build. | M6 | R6.2, AC#10, AC#11, Survey |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|---|---|---|---|
| M0 | E2E Test Suite Track | Requirement-driven opaque-box test harness & test suite (Tiers 1-4) covering all 22 features, publishing TEST_READY.md | none | PLANNED |
| M1 | Audio Playback & Karaoke Sync | FEAT-R1-01 through FEAT-R1-06 (Word tokens, AVPlayer controller, vDSP Waveform, Karaoke highlight, click-to-seek, media retention) | none | PLANNED |
| M2 | Audio & Mic Recording Engine | FEAT-R2-01 through FEAT-R2-05 (AVAudioEngine recorder, vDSP metering, live waveform UI, auto-save/transcribe, entitlements) | none | PLANNED |
| M3 | Diarization & Inline Editor | FEAT-R3-01 through FEAT-R3-05 (Acoustic turn diarization, colored badges, inline editable view, atomic DB sync, NL summarizer) | M1 | PLANNED |
| M4 | Menu Bar & Drop-Zone | FEAT-R4-01, FEAT-R4-02 (Menu bar drag-and-drop, floating drop widget, quick dictation toggle) | M2 | PLANNED |
| M5 | macOS Sequoia HIG & Shortcuts | FEAT-R5-01, FEAT-R5-02 (Liquid Glass vibrancy, 3-column navigation, ⌘K, Space, ⌘F, ⌘E shortcuts, Quick Look) | M1, M3 | PLANNED |
| M6 | E2E Integration Pass & Hardening | Phase 1: 100% E2E test pass (Tiers 1-4); Phase 2: Adversarial coverage hardening (Tier 5), DMG audit, zero regressions | M0, M1, M2, M3, M4, M5 | PLANNED |

## Interface Contracts

### AudioPlayerController ↔ KaraokeTranscriptView
```swift
@MainActor
public protocol AudioPlaybackControlling: ObservableObject {
    var currentTime: Double { get }
    var duration: Double { get }
    var isPlaying: Bool { get }
    func load(url: URL) async throws
    func play()
    func pause()
    func togglePlayPause()
    func seek(to time: Double)
}
```

### WaveformGenerator (Accelerate/vDSP)
```swift
public struct WaveformPoint: Sendable, Codable, Equatable {
    public let min: Float
    public let max: Float
}

public protocol WaveformGenerating: Sendable {
    func generateWaveform(from audioURL: URL, targetPoints: Int) async throws -> [WaveformPoint]
}
```

### AudioRecordingEngine ↔ LiveAudioMeterView
```swift
@MainActor
public protocol AudioRecordingControlling: ObservableObject {
    var isRecording: Bool { get }
    var currentMeteringLevel: Float { get } // 0.0 to 1.0 (RMS dB scaled)
    var frequencyBands: [Float] { get }      // e.g. 16/32 bands via vDSP FFT
    func startRecording() async throws -> URL
    func stopRecording() async throws -> URL
}
```

### Diarization & Inline Editor ↔ AppDatabase
```swift
public struct Word: Codable, Sendable, Equatable {
    public let text: String
    public let start: Double // seconds
    public let end: Double   // seconds
    public let confidence: Float
}

public struct Segment: Codable, Sendable, Equatable {
    public var start: Double
    public var end: Double
    public var text: String
    public var speaker: String?
    public var words: [Word]
}

extension AppDatabase {
    public func updateTranscript(jobId: String, newText: String, segments: [Segment]) async throws
}
```

## Code Layout
- `Sources/TranskriptHubCore/Audio/`
  - `AudioDecoder.swift` (existing)
  - `AudioValidator.swift` (existing)
  - `AudioPlayerController.swift` (new — AVFoundation playback controller)
  - `WaveformGenerator.swift` (new — Accelerate/vDSP waveform downsampling)
  - `AudioRecordingEngine.swift` (new — AVAudioEngine recording & live tap)
- `Sources/TranskriptHubCore/Transcription/`
  - `TranscriptionModels.swift` (updated — Word struct, speaker & words in Segment)
  - `WhisperCppEngine.swift` (updated — wparams.token_timestamps = true & token extraction)
  - `SpeakerDiarizer.swift` (new — acoustic turn & pause clustering via vDSP)
  - `LocalSummarizer.swift` (new — NaturalLanguage summarization & chaptering)
- `Sources/TranskriptHubApp/Views/`
  - `ContentView.swift` (updated — 3-column NavigationSplitView with SidebarView)
  - `SidebarView.swift` (existing, wired into ContentView)
  - `TranscriptDetailView.swift` (updated — hosting interactive waveform, karaoke, and editor)
  - `WaveformVisualizerView.swift` (new — 60/120fps scrub, timeline, click-to-seek)
  - `KaraokeTranscriptView.swift` (new — word illumination & millisecond seek)
  - `InlineTranscriptEditorView.swift` (new — AppKit/SwiftUI editable view with speaker badges)
  - `LiveAudioMeterView.swift` (new — animated Voice Memos-style frequency bars)
  - `MenuBarMiniWindow.swift` (updated — drag-and-drop zone & quick record)
  - `FloatingDropZoneView.swift` (new — quick drop panel)
- `Tests/TranskriptHubCoreTests/`
  - Existing 14 test suites (all 39 tests preserved)
  - `AudioPlayerControllerTests.swift` (new)
  - `WaveformGeneratorTests.swift` (new)
  - `AudioRecordingEngineTests.swift` (new)
  - `SpeakerDiarizerTests.swift` (new)
  - `InlineTranscriptDatabaseTests.swift` (new)
  - `E2ETestSuite/` (new — requirement-driven opaque-box test suites for Tiers 1-4)
