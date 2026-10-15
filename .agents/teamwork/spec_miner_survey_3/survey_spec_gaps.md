# Transkript Hub — Comprehensive Specification & Gap Analysis Report
*Survey Phase — Spec Miner 3 Report*
*Date: 2026-10-15*

---

## 1. Executive Summary

Transkript Hub currently possesses a robust, working core for offline YouTube and local file transcription using `whisper.cpp` (Metal GPU accelerated) and `GRDB.swift` for SQLite persistence. All **39 unit and integration tests** currently pass cleanly in under 0.03 seconds, and the release build packages into a **7.4 MB DMG** (`dist/TranskriptHub.dmg`), well within the target threshold of <10 MB / <15 MB.

However, against the AAA Apple 1st-party requirements specified in `ORIGINAL_REQUEST.md`, significant architectural and user-interface gaps exist across Requirements R1 through R6:
- **Audio Playback & Waveform (R1)**: No audio player exists in the app. Waveform is merely an SF Symbol icon; no waveform extraction (via `Accelerate/vDSP`) or interactive scrub visualizer exists. `whisper.cpp` is currently queried only at segment boundaries without token/word timestamps (`wparams.token_timestamps` is not set).
- **In-App Recording Engine (R2)**: Direct audio recording is completely missing. No `AVAudioEngine` or `AVAudioRecorder` implementation exists, microphone entitlements are missing, and no live audio meter or animated visualizer exists.
- **Speaker Diarization & Inline Editor (R3)**: Speaker diarization was originally labeled "Out of Scope" in the legacy spec (`TRANSKRIPT_HUB_SPEC.md` line 48), so the data models (`Segment`, `TranscriptSectionRecord`) and UI lack speaker attributions. Furthermore, `NativeTranscriptTextView` explicitly sets `textView.isEditable = false`, completely preventing inline editing. Summaries, action items, and chaptering are also absent.
- **Menu Bar Companion & Drop-Zone (R4)**: While `MenuBarExtra` exists with `MenuBarMiniWindow`, it lacks drag-and-drop audio file handling, lacks a floating drop-zone widget, and has no global hotkey or quick-record shortcut.
- **macOS Ecosystem & HIG Ergonomics (R5)**: Spacebar play/pause, ⌘F interactive search navigation, ⌘E multi-format export (SRT, VTT, JSON, Markdown), and Quick Look media previews (`QLPreviewPanel`) are missing.
- **Performance & Zero Dependencies (R6)**: The project maintains a clean zero-dependency posture (only `whisper.xcframework` and `GRDB.swift`), but Accelerate/vDSP is not yet utilized for signal processing or audio downsampling.

---

## 2. Requirements Gap Matrix (R1 – R6 & Acceptance Criteria)

### 2.1 Requirements Breakdown

| Requirement ID | Requirement Description | Status | Current Codebase State | Changes Required |
|---|---|---|---|---|
| **R1.1** | AVFoundation audio playback synchronized with word & segment timestamps | **MISSING** | No audio player exists (`AVAudioPlayer`/`AVPlayer` absent). `Segment` model (`TranscriptionModels.swift:3-13`) only has `start, end, text`. Temporary audio from YouTube is removed post-transcription (`JobManager.swift:984`). | Build `AudioPlayerEngine` with AVFoundation; enable `wparams.token_timestamps` in `WhisperCppEngine.swift`; add `WordTiming` to `Segment`; persist audio files for playback. |
| **R1.2** | Responsive Apple Voice Memos interactive waveform visualizer with click-to-seek & scrub | **MISSING** | Only SF Symbol `"waveform"` is rendered (`TranscriptDetailView.swift:357`). Zero waveform sample processing. | Extract RMS/peak amplitude samples via `Accelerate/vDSP`; create `InteractiveWaveformView` with SwiftUI `Canvas`/`TimelineView` supporting 60/120 fps scrubbing. |
| **R1.3** | Karaoke-style active word highlighting & click-to-jump millisecond seek | **MISSING** | `NativeTranscriptTextView.swift:33` is read-only `NSTextView` with plain text string. | Create word-segmented interactive text component; track active word via playback clock; seek player to `word.start` on click. |
| **R2.1** | Direct audio recording engine via `AVAudioEngine` / `AVAudioRecorder` | **MISSING** | No recording code exists. Entitlements lack `com.apple.security.device.audio-input`. | Build `AudioRecordingEngine` using `AVAudioEngine.inputNode`; add microphone entitlements and `NSMicrophoneUsageDescription`. |
| **R2.2** | Animated live audio meter / frequency bar visualizer during recording | **MISSING** | No audio metering or frequency visualization exists. | Install tap on audio bus; compute volume/frequency bands via `vDSP_rmsqv`/FFT; build animated `LiveAudioMeterView`. |
| **R2.3** | One-click transcription upon recording stop, auto-save to history & export | **MISSING** | Queue only supports `.youtube` and `.audioFile(URL)` (`QueueItem.swift:4-7`). | Add `.recordedAudio(URL)` kind; connect stop action to auto-save, auto-enqueue, Whisper transcription, and output export. |
| **R3.1** | Speaker Diarization with distinct colored badges & editable custom names | **MISSING** | Legacy spec marked diarization out of scope. Segments have no speaker metadata. | Implement energy/pause-based acoustic turn clustering via `vDSP`; add `speakerId`/`speakerName` to `Segment`; render color-coded badge pills. |
| **R3.2** | Inline rich transcript editing with atomic SQLite updates | **MODIFICATION NEEDED** | `NativeTranscriptTextView.swift:33` sets `textView.isEditable = false`. `AppDatabase` lacks direct segment/text update API. | Enable editing in text view or segment editor; add `updateTranscriptText(jobID:text:segments:)` to `AppDatabase` with atomic transaction. |
| **R3.3** | Local summary, bullet-point action items, and timestamped chaptering | **MISSING** | No summarization or chapter generation exists. | Build `LocalContentAnalyzer` using Apple `NaturalLanguage` (`NLTokenizer`, `NLEmbedding`); detect silence chapters and extract key takeaways. |
| **R4.1** | Menu Bar extra with drag-and-drop & Floating Drop-Zone Widget | **MODIFICATION NEEDED** | `MenuBarExtra` exists (`TranskriptHubApp.swift:89`), but `MenuBarMiniWindow.swift` lacks file drop. No floating panel exists. | Add `.onDrop(of: [.fileURL])` to Menu Bar mini window; create `FloatingDropZonePanel` (`NSPanel`). |
| **R4.2** | Global hotkey & quick-record toggle for instantaneous dictation | **MISSING** | Keyboard handling is local to window (`KeyInterceptingView` in `ContentView.swift:389`). | Add global hotkey listener via `NSEvent.addGlobalMonitorForEvents` or Carbon HotKey; add quick-record button in Menu Bar. |
| **R5.1** | Modern Liquid Glass design language (NSVisualEffectView, SF Symbols 6, unified toolbar) | **EXISTS / NEEDS REFINEMENT** | `LiquidGlass.swift` and `VisualEffectView.swift` exist. UI uses `.ultraThinMaterial` and capsules. | Refine layout to strictly adhere to 3-column `design.md` spec; apply Liquid Glass styling to new waveform, player, and recorder controls. |
| **R5.2** | Native keyboard shortcuts (⌘K palette, Space play/pause, ⌘F search navigation, ⌘E export) | **MODIFICATION NEEDED** | ⌘K exists. ⌘V, ⌘A, ⇧⌘C exist. Spacebar play/pause, ⌘F search hit navigation, and ⌘E multi-format export are missing. | Implement Spacebar transport interceptor; build ⌘F find bar with hit navigation; implement ⌘E export action sheet. |
| **R5.3** | Quick Look previews & Apple Voice Memos / iCloud Drive integration | **MODIFICATION NEEDED** | `FolderWatcher.swift:54-77` watches Voice Memos & iCloud folders. Quick Look preview (`QLPreviewPanel`) is absent. | Implement `quickLookPreview` or `QLPreviewView` for media items; provide iCloud auto-export option. |
| **R6.1** | Ultra-lean footprint (<10 MB DMG distribution) | **EXISTS** | `dist/TranskriptHub.dmg` is currently **7.4 MB**. | Ensure all new modules use native Apple frameworks to keep DMG size well below 10 MB / 15 MB. |
| **R6.2** | Swift 6 Concurrency, zero-copy memory transfers, Accelerate/vDSP | **MODIFICATION NEEDED** | Swift 6 strict concurrency enabled (`Package.swift:38`). Accelerate/vDSP is not yet imported anywhere in Sources. | Import `Accelerate` for audio processing (vDSP); use actors for recording and playback state. |
| **R6.3** | Zero extraneous 3rd-party dependencies (strictly Apple native) | **EXISTS** | Only `GRDB.swift` and `whisper.xcframework` used. | Maintain zero additional SPM packages. |

---

### 2.2 Acceptance Criteria Verification Matrix

| # | Acceptance Criterion | Current Status | Cause of Failure / Gap | Required Remediation |
|---|---|---|---|---|
| **AC1** | Clicking any word jumps audio playback to exact timestamp (±100ms accuracy) | ❌ **FAIL** | No audio player; no word-level timestamps in Whisper engine. | Implement `AudioPlayerEngine` with `seek(to: CMTime, toleranceBefore: .zero, toleranceAfter: .zero)`; extract token timestamps from `whisper.cpp`. |
| **AC2** | Waveform scrubs smoothly at 60/120 fps during playback without UI hitching | ❌ **FAIL** | No waveform rendering component; no scrub gesture. | Downsample audio with `vDSP_maxv`; render using SwiftUI `Canvas` or `TimelineView` with gesture scrub binding. |
| **AC3** | Spacebar toggles playback; controls reflect exact position & total duration | ❌ **FAIL** | Spacebar is unhandled; no transport bar. | Add Space key interceptor; create `AudioTransportBar` bound to player position and duration. |
| **AC4** | Direct recording starts/stops cleanly via microphone; saved as uncompressed/AAC | ❌ **FAIL** | No recording engine in codebase. | Implement `AudioRecordingEngine` saving to `.m4a` (AAC) or `.wav` (PCM). |
| **AC5** | Live audio waveform/meter reacts in real time to input volume | ❌ **FAIL** | No live audio input tap or volume meter. | Tap `inputNode` in `AVAudioEngine`, compute RMS via `vDSP_rmsqv`, drive dynamic SwiftUI meter. |
| **AC6** | Speaker badges are clearly distinguished and allow inline renaming | ❌ **FAIL** | No diarization; no speaker model; no speaker badges. | Cluster segment audio into speaker turns; provide editable color-coded badge pills. |
| **AC7** | Editing transcript text updates underlying database model atomically | ❌ **FAIL** | Transcript view is explicitly non-editable (`isEditable = false`). | Enable inline editing; execute atomic `UPDATE transcript_section` query in `AppDatabase`. |
| **AC8** | Packaged DMG binary size remains strictly under 15 MB | ✅ **PASS** | Current DMG size is 7.4 MB. | Maintain zero-dependency discipline. |
| **AC9** | App launches in under 200 ms on Apple Silicon | ✅ **PASS** | Lightweight startup without heavy runtimes. | Maintain lazy loading and avoid main-thread blocking on startup. |
| **AC10**| All 39 existing unit & integration tests continue to pass without regressions | ✅ **PASS** | 39 of 39 tests passing (`swift test`). | Retain all existing contracts while expanding functionality. |
| **AC11**| swift build compiles cleanly with zero warnings or errors | ✅ **PASS** | `swift build` produces 0 errors, 0 warnings. | Strict Swift 6 compliance for all new code. |

---

## 3. Deep Architectural & Codebase Inspection

### 3.1 Audio Ingestion & Playback Pipeline (R1)
- **Current Observation**:
  - `Sources/TranskriptHubCore/Audio/AudioDecoder.swift` converts audio to 16 kHz Float32 mono PCM via `AVAudioConverter`.
  - When YouTube videos are transcribed, line 981 of `AppViewModel.swift` creates a temporary directory:
    ```swift
    let itemWorkspace = FileManager.default.temporaryDirectory
        .appendingPathComponent("transkript_\(item.id)_\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: itemWorkspace) }
    ```
    This immediately deletes the audio file after transcription finishes! For synchronized audio playback, the audio file (or converted AAC audio) must be stored in a dedicated persistent directory (e.g. `Application Support/TranskriptHub/AudioCache/`).
- **Whisper Token Timestamp Discovery**:
  - Inspection of `Frameworks/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Headers/whisper.h` reveals full support for token timestamps:
    - `wparams.token_timestamps = true;` (line 505)
    - `whisper_full_n_tokens(ctx, i_segment)` (line 655)
    - `whisper_full_get_token_text(ctx, i_segment, i_token)` (line 659)
    - `whisper_full_get_token_t0(ctx, i_segment, i_token)` (line 675)
    - `whisper_full_get_token_t1(ctx, i_segment, i_token)` (line 677)
  - `WhisperCppEngine.swift` currently extracts only segments:
    ```swift
    let t0 = Double(whisper_full_get_segment_t0(context, i)) / 100.0
    let t1 = Double(whisper_full_get_segment_t1(context, i)) / 100.0
    let textPtr = whisper_full_get_segment_text(context, i)
    ```
    By setting `wparams.token_timestamps = true` and iterating `whisper_full_n_tokens`, word tokens can be assembled into `WordTiming(word: String, start: Double, end: Double)` with millisecond accuracy.

### 3.2 In-App Recording Architecture (R2)
- **Current Observation**:
  - Zero microphone or recording APIs are utilized.
  - `Resources/TranskriptHub.entitlements` lacks:
    ```xml
    <key>com.apple.security.device.audio-input</key>
    <true/>
    ```
  - `scripts/package_dmg.sh` generates `Info.plist` without `NSMicrophoneUsageDescription`.
- **Target Architecture**:
  - `AudioRecordingEngine`: Actor wrapping `AVAudioEngine`.
  - Tap `inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat)` to feed both a file sink (`AVAudioFile` writing AAC/PCM) and a real-time metering publisher.
  - Compute RMS and peak levels using `vDSP_rmsqv` to feed `LiveAudioMeterView`.
  - On stop, persist file to `~/Library/Application Support/TranskriptHub/Recordings/` and emit URL to `AppViewModel`.

### 3.3 Speaker Diarization & Inline Editor (R3)
- **Current Observation**:
  - `TRANSKRIPT_HUB_SPEC.md` line 48 listed speaker diarization as out-of-scope, but `ORIGINAL_REQUEST.md` makes it a mandatory core requirement (R3).
  - In `NativeTranscriptTextView.swift:33`:
    ```swift
    textView.isEditable = false
    textView.isSelectable = true
    ```
  - In `AppDatabase.swift`, the `transcript_section` table stores:
    ```sql
    CREATE TABLE transcript_section (
      job_id TEXT PRIMARY KEY REFERENCES job(id) ON DELETE CASCADE,
      text TEXT NOT NULL,
      segments TEXT
    );
    ```
- **Target Architecture**:
  - **Diarization**: In offline transcription, acoustic turns can be clustered by extracting acoustic features (energy profile, spectral centroid via `vDSP`, or pause thresholds $>1.2$s) to assign `speakerId: "SPEAKER_01"`, `"SPEAKER_02"`.
  - **Badges**: Distinct Apple-style Liquid Glass badge capsules with customizable labels (e.g. `SpeakerMapping[speakerId] = "Akif"`).
  - **Inline Editing**: Allow `NSTextView` to be editable or provide segment-level editable text fields that dispatch `AppDatabase.shared.updateTranscriptSection(jobID:text:segments:)` inside a GRDB write transaction.
  - **Local Summarization**: Use Apple's built-in `NaturalLanguage` framework (`NLTokenizer`, `NLEmbedding`, `NLLanguageRecognizer`) to extract top key sentences (extractive summary) and action items (sentences starting with action verbs/imperatives) with zero cloud dependencies.

### 3.4 Menu Bar & Desktop Ergonomics (R4 & R5)
- **Current Observation**:
  - `TranskriptHubApp.swift:89-93` declares `MenuBarExtra("Transkript Hub", ...) { MenuBarMiniWindow(viewModel: viewModel) }`.
  - `MenuBarMiniWindow.swift` has a text field for YouTube links, but lacks file drop support (`.onDrop`).
  - No global keyboard shortcut registration exists (`KeyInterceptingView` only listens to window-level events).
- **Target Architecture**:
  - Add drag-and-drop support (`.onDrop(of: [.fileURL])`) to `MenuBarMiniWindow`.
  - Implement `FloatingDropZonePanel`: borderless translucent `NSPanel` with `.floating` window level that accepts audio file drops from Finder.
  - Register global hotkey monitor (`NSEvent.addGlobalMonitorForEvents(matching: .keyDown)`) or status item action to toggle dictation recording.
  - Implement full keyboard suite:
    - `Space`: audio play/pause toggle.
    - `⌘F`: native search bar with match count and jump navigation.
    - `⌘E`: multi-format export sheet (Plain Text, SRT, VTT, JSON, Markdown).

---

## 4. Apple Frameworks & Native APIs Enumeration

The entire AAA feature set can be implemented with **100% native Apple frameworks** and **zero new third-party dependencies**:

| Framework | Specific Classes / Functions | Primary Responsibility |
|---|---|---|
| **AVFoundation** | `AVAudioPlayer` / `AVPlayer`, `AVPlayerItem`, `CMTime`, `addPeriodicTimeObserver(forInterval:queue:using:)`, `seek(to:toleranceBefore:toleranceAfter:)` | Synchronized audio playback, accurate millisecond seeking, time observation. |
| **AVFoundation** | `AVAudioEngine`, `AVAudioInputNode`, `AVAudioFile`, `AVAudioFormat`, `AVAudioPCMBuffer`, `AVAudioConverter`, `installTap(onBus:bufferSize:format:block:)` | In-app microphone recording, low-latency audio capture, real-time audio bus tapping. |
| **AVFoundation** | `AVCaptureDevice.authorizationStatus(for: .audio)`, `AVCaptureDevice.requestAccess(for: .audio)` | Microphone permission management and privacy compliance. |
| **Accelerate / vDSP** | `vDSP_rmsqv`, `vDSP_maxv`, `vDSP_vabs`, `vDSP_desamp` | High-performance SIMD calculation of RMS audio volume, peak levels, and waveform downsampling. |
| **Accelerate / vDSP** | `vDSP_fft_zrip`, `vDSP_zvabs` | Real-time Fast Fourier Transform for live frequency bar audio meter. |
| **NaturalLanguage** | `NLTokenizer`, `NLEmbedding`, `NLLanguageRecognizer` | On-device sentence extraction, topic boundary detection, and local extractive summarization / action item extraction. |
| **AppKit** | `NSStatusItem`, `NSStatusBar`, `NSPanel`, `NSWindow`, `NSOpenPanel`, `NSPasteboard`, `NSEvent` | Menu Bar companion, floating drop-zone window, global hotkey monitoring, file dialogues. |
| **AppKit** | `NSTextView`, `NSTextStorage`, `NSLayoutManager`, `NSTextContainer` | Native rich text editing, interactive click ranges, attributed word highlighting. |
| **QuickLook / QuickLookUI** | `QLPreviewPanel`, `QLPreviewItem`, `quickLookPreview` | Instant Quick Look audio/video media preview triggered by Spacebar or menu action. |
| **SwiftUI** | `Canvas`, `TimelineView`, `Path`, `NavigationSplitView`, `VisualEffectView`, `.onDrop` | 60/120 fps waveform rendering, Liquid Glass vibrancy, 3-column macOS desktop ergonomics. |
| **CryptoKit** | `SHA256` | Content hashing, deduplication, and tool integrity verification. |
| **OSLog** | `os.Logger(subsystem:category:)` | Privacy-compliant diagnostic logging without persisting transcript text. |

---

## 5. Feature Inventory Proposal

| Feature ID | Category | Feature Name | Description | Dependencies | Complexity |
|---|---|---|---|---|---|
| **FEAT-R1-01** | Playback | `AudioPlayerEngine` | Native AVFoundation audio playback service supporting play, pause, seek, rate control, and high-frequency time publishing. | AVFoundation | Medium |
| **FEAT-R1-02** | Playback | `TokenWordAligner` | Whisper.cpp token timestamp extraction (`wparams.token_timestamps = true`) and word-level timing model (`WordTiming`). | whisper.h, TranskriptHubCore | Medium |
| **FEAT-R1-03** | Waveform | `WaveformExtractor` | Accelerate/vDSP-powered audio reader extracting RMS/peak amplitude downsampled bars (100–500 buckets). | Accelerate/vDSP, AVFoundation | Medium |
| **FEAT-R1-04** | Waveform | `InteractiveWaveformView` | Apple Voice Memos-style interactive waveform visualizer with click-to-seek, scrub gestures, and 60/120 fps smooth playhead. | SwiftUI Canvas, TimelineView, FEAT-R1-01 | High |
| **FEAT-R1-05** | Playback | `KaraokeWordHighlighter` | Synchronized word illumination during playback, with click-to-jump millisecond seeking (±100ms accuracy). | FEAT-R1-01, FEAT-R1-02 | High |
| **FEAT-R2-01** | Recording | `AudioRecordingEngine` | Microphone recording engine powered by `AVAudioEngine.inputNode`, saving AAC/PCM to audio storage with permission flow. | AVFoundation, Entitlements | Medium |
| **FEAT-R2-02** | Recording | `LiveAudioMeterView` | Real-time animated volume meter and frequency bar visualizer reacting dynamically to mic input volume. | Accelerate/vDSP, SwiftUI, FEAT-R2-01 | Medium |
| **FEAT-R2-03** | Recording | `RecordingPipelineCoordinator` | One-click auto-stop, auto-save to history, automatic queue insertion, transcription, and text file export. | FEAT-R2-01, JobManager, OutputWriter | Medium |
| **FEAT-R3-01** | Diarization | `SpeakerDiarizer` | Acoustic pause and energy turn clustering categorizing transcript segments into Speaker 1, Speaker 2, etc. | Accelerate/vDSP, TranscriptionModels | High |
| **FEAT-R3-02** | Diarization | `SpeakerBadgeView` | Distinct Apple-style colored badge capsules per speaker turn, with inline editable custom names. | SwiftUI, FEAT-R3-01 | Low |
| **FEAT-R3-03** | Editor | `InlineTranscriptEditor` | Editable transcript view supporting inline term correction with atomic SQLite database persistence. | AppKit (NSTextView), GRDB | Medium |
| **FEAT-R3-04** | Analysis | `LocalContentAnalyzer` | Local extractive summary, bullet-point action item generation, and timestamped chaptering using Apple NaturalLanguage. | NaturalLanguage, Accelerate | Medium |
| **FEAT-R4-01** | MenuBar | `MenuBarDropTarget` | Drag-and-drop audio file handling directly onto the Menu Bar companion window. | AppKit, SwiftUI (.onDrop) | Low |
| **FEAT-R4-02** | MenuBar | `FloatingDropZonePanel` | Translucent Liquid Glass floating desktop drop-zone widget (`NSPanel`) for quick drag-and-drop ingestion. | AppKit (NSPanel), SwiftUI | Medium |
| **FEAT-R4-03** | Hotkey | `GlobalHotkeyManager` | Global hotkey monitor for instantaneous dictation recording toggle from any macOS application. | AppKit (NSEvent), FEAT-R2-01 | Medium |
| **FEAT-R5-01** | UI/HIG | `LiquidGlassStudioRefinement` | 3-Column NavigationSplitView conforming to `design.md` §5 with Liquid Glass specular highlights and materials. | SwiftUI, LiquidGlass.swift | Low |
| **FEAT-R5-02** | Ergonomics | `KeyboardShortcutsSuite` | Full desktop keyboard suite: Space (play/pause), ⌘F (find with hit navigation), ⌘E (export), ⌘K (palette). | AppKit (NSEvent), SwiftUI | Medium |
| **FEAT-R5-03** | Ecosystem | `MediaQuickLookCoordinator` | Quick Look preview for source audio/video files via `QLPreviewPanel`. | QuickLook / QuickLookUI | Low |
| **FEAT-R5-04** | Export | `MultiFormatExporter` | Multi-format transcript exporter producing SRT, VTT, JSON, Markdown, and formatted Plain Text. | TranskriptHubCore | Medium |
| **FEAT-R6-01** | Performance | `BinarySizeAndLaunchGuard` | Packaging and startup optimization guaranteeing <10 MB DMG distribution and <200 ms launch on Apple Silicon. | scripts/package_dmg.sh | Low |

---

## 6. Technical Risks & Architectural Mitigations

1. **Risk: Temporary Audio File Deletion Prevents Playback (R1)**
   - *Detail*: Current `JobManager` cleans up temporary workspace files immediately after transcription. For playback to work, audio files must be accessible.
   - *Mitigation*: Introduce `AudioStorageManager` in `TranskriptHubCore` that retains audio in `~/Library/Application Support/TranskriptHub/Audio/` with configurable retention/cleanup.
2. **Risk: Microphone Permission Crashes in Hardened Runtime (R2)**
   - *Detail*: Attempting to record without `com.apple.security.device.audio-input` or `NSMicrophoneUsageDescription` will crash the process on macOS 14+.
   - *Mitigation*: Update `Resources/TranskriptHub.entitlements` and `scripts/package_dmg.sh` Info.plist generation immediately before testing recording features.
3. **Risk: Main Thread Hitching During Waveform Scrubbing (AC2)**
   - *Detail*: Computing waveform amplitudes on the fly during scrubbing causes frame drops below 60 fps.
   - *Mitigation*: Pre-compute and cache downsampled amplitude arrays (Float array of ~200-400 values) on a background actor using `vDSP_maxv`. The UI canvas only renders the pre-computed array.
4. **Risk: Word-Level Timestamp Performance Overhead (R1)**
   - *Detail*: Enabling `wparams.token_timestamps = true` in `whisper.cpp` can add minor CPU overhead.
   - *Mitigation*: Whisper Metal acceleration handles token timestamps efficiently without noticeable latency increase on Apple Silicon.
5. **Risk: Regressions in Existing 39 Tests (AC10)**
   - *Detail*: Altering `Segment` or `TranscriptSectionRecord` models could break existing database migrations or JSON deserialization.
   - *Mitigation*: Maintain backward compatibility by providing default values (`words: [WordTiming] = []`, `speaker: String? = nil`) and adding database migration `v3_words_and_speakers`.
