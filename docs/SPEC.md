# Transkript Hub — Master Specification (v1)

This specification defines the binding architecture and operational contracts for Transkript Hub. It is also preserved under `docs/SPEC.md`. Every architectural rule, state transition, and operational constraint is binding.

---

### 0. Role and Operational Principles

- You are the Lead Architect and Core Engineer for this project. Decisions in this specification are binding; if a revision is necessary, justify and confirm before writing code.
- Complete each milestone independently. Do not proceed to the next milestone until acceptance criteria are satisfied.
- First build `TranskriptHubCore` (UI-free pure Swift package); the UI layer depends entirely on the core. Every public type in Core must be fully testable.
- All code must target Swift 6 with strict concurrency enabled. Internal code identifiers, types, comments, and logging must be in English. User-facing strings support English (default), German, and Turkish.
- External dependencies are strictly limited to: `whisper.cpp` (xcframework), `GRDB.swift`, and Sparkle 2. Do not add unapproved dependencies.
- Legacy shell scripts (`docs/legacy-reference/`) serve solely as behavioral references; do not copy shell scripts, reimplement cleanly in native Swift.
- Every operation must be strictly idempotent: interrupting a step and re-running it must produce the exact same deterministic outcome.
- Never delete, move, or modify original user media files unless explicitly configured by the user (§8.5).

---

### 1. Product Definition

**Transkript Hub** is a self-contained, native macOS application built for Apple Silicon Macs that converts audio into text entirely on-device. Users collect YouTube links (via clipboard or direct paste) or supply local audio files; the application downloads/extracts audio, transcribes it locally using `whisper.cpp` on the Metal GPU, and formats the output into clean plain text (`.txt`) documents in the designated output folder. When processing finishes, only clean `.txt` files remain. Users never need to install or run Terminal, Homebrew, Python, Buzz, FFmpeg, or yt-dlp.

Primary use case: *"Select 5–50 YouTube videos for research → obtain a single consolidated, formatted transcript document."*

---

### 2. Scope

**v1 (Current Scope)**
- macOS 14+ (Sonoma and Sequoia), Apple Silicon (arm64) only.
- YouTube: single video, bulk multi-link paste, smart clipboard monitoring (when application is running and capture is enabled).
- Local files: drag-and-drop, native open file panel. Supported formats: any audio/video container readable by AVFoundation (`m4a`, `mp3`, `wav`, `aac`, `caf`, `aiff`, `mp4`, `mov`).
- Watched folders, including iCloud Drive directories (with automatic dateless `.icloud` placeholder download handling).
- `whisper.cpp` + `large-v3-turbo` + Silero VAD v6.2.0; language: automatic detection or user-specified.
- Batch modes: multi-source → single merged `.txt`, or individual `.txt` titled after each item, or both.
- SQLite persistence, crash recovery, automatic cleanup, sleep prevention during transcription.
- Menu Bar icon helper: processing continues seamlessly in the background when the main window is closed.
- `ToolManager`: downloads, validates, and manages isolated `yt-dlp` and `Deno` binaries.
- `ModelManager`: downloads and verifies Whisper models locally.
- Sparkle 2 updater, Developer ID signing, and notarization compatibility.

**v1.1 (Future Considerations)**
- Voice Memos Share Extension; Voice Memos Group Container direct watcher with Full Disk Access.
- SRT / VTT / JSON structured export formats, RSS / podcast feeds, Core ML encoder acceleration.

**Out of Scope**
- Windows / Linux / iOS, cloud-based transcription, remote LLM summarization, speaker diarization, automated translation, account authentication / paywalls, Mac App Store sandboxed distribution, Intel Macs.

---

### 3. Core Architectural Decisions

| Topic | Decision |
|---|---|
| **Language & UI** | Swift 6, SwiftUI; AppKit where necessary (`NSPasteboard`, `NSStatusItem`, `NSApp` activation policy) |
| **Distribution** | Developer ID signed, Hardened Runtime, notarized DMG. App Sandbox **disabled**. |
| **Transcription Engine** | Official `whisper.xcframework` (C/C++ runtime), Metal GPU acceleration enabled, Core ML disabled |
| **Model** | `ggml-large-v3-turbo.bin` (f16, 1.62 GB) for RAM ≥ 16 GB; `ggml-large-v3-turbo-q5_0.bin` (574 MB) for RAM < 16 GB. VAD: `ggml-silero-v6.2.0.bin`. Source: Hugging Face `ggerganov/whisper.cpp` & `ggml-org/whisper-vad`. Fixed SHA-256 manifests. |
| **Audio Decoding** | AVFoundation (`AVAudioFile` / `AVAssetReader`) → 16 kHz mono Float32 PCM in-memory. Zero FFmpeg dependency. |
| **YouTube Fetch** | Official `yt-dlp_macos` executable + Deno managed by `ToolManager` under `~/Library/Application Support/<bundle-id>/Tools/`. Executed via `Process`. |
| **Database** | SQLite via GRDB.swift, WAL mode, strictly ordered `DatabaseMigrator`. |
| **Logging** | `os.Logger` (subsystem = bundle ID) + rolling file log (`Logs/app.log`, 5 MB × 3). |
| **Background Execution** | Single-process architecture; window closure sets `NSApp.setActivationPolicy(.accessory)`. Login item: `SMAppService.mainApp`. |
| **Sleep Prevention** | While batches are active: `ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason:)`. |
| **Updates** | Application: Sparkle 2 (EdDSA). Tools: `ToolManager`. Models: `ModelManager`. |

---

### 4. Modules and Responsibilities

```
TranskriptHub (Xcode app target)
├── App/            TranskriptHubApp, AppDelegate (menu bar, activation policy), AppViewModel
├── DesignSystem/   LiquidGlass, VisualEffectView, responsive layout modifiers
├── Models/         QueueItem, HistoryItem, BatchScopeSelection
├── Views/          ContentView, SidebarView, QueueListView, HistoryListView, WatchedFolderView, FloatingSettingsSheet
└── TranskriptHubCore (Pure Swift package, no UI dependencies)
    ├── Database/        AppDatabase (GRDB), migrations, database record types
    ├── Jobs/            JobManager (actor orchestrator), JobState, transition rules
    ├── Sources/         SourceInput, URLParser, YouTubeMetadataResolver, FolderWatcher
    ├── Tools/           ToolManager (yt-dlp, Deno), YTDLPClient
    ├── Audio/           AudioDecoder (AVFoundation → PCM), AudioValidator, PreparedAudio
    ├── Transcription/   TranscriptionEngine (protocol), WhisperCppEngine, ModelManager, TranscriptPostProcessor, WhisperModelCatalog
    ├── Cache/           TranscriptCacheManager (smart deduplication by title, duration, external ID)
    ├── Batch/           BatchAssembler, OutputFormatter (Format-Version 1)
    ├── Output/          OutputWriter (atomic write, filename sanitization, collision handling)
    ├── Cleanup/         CleanupManager
    ├── Permissions/     FullDiskAccessHelper
    ├── System/          ClipboardMonitor, SleepGuard, DiskSpaceChecker
    └── Logging/         Log, DiagnosticsExporter
```

Core Protocols:

```swift
public protocol SourceAdapter: Sendable {
    func canHandle(_ input: SourceInput) -> Bool
    func resolve(_ input: SourceInput) async throws -> ResolvedSource
}

public protocol MediaFetcher: Sendable {
    func fetch(_ source: ResolvedSource, into workspace: URL,
               progress: @Sendable (Double) -> Void) async throws -> URL
}

public protocol TranscriptionEngine: Sendable {
    func transcribe(_ audio: PreparedAudio, options: TranscriptionOptions,
                    progress: @Sendable (Double) -> Void) async throws -> TranscriptResult
}

public struct TranscriptionOptions: Sendable {
    public var language: String?        // nil = auto
    public var useVAD: Bool             // default true
    public var threads: Int             // default: performance core count
    public var initialPrompt: String?   // optional terminology hints
}

public struct TranscriptResult: Sendable {
    public var segments: [Segment]      // start, end (seconds), text
    public var detectedLanguage: String?
}
```

---

### 5. Data Model (SQLite)

```sql
CREATE TABLE batch (
  id              TEXT PRIMARY KEY,           -- UUID
  created_at      TEXT NOT NULL,              -- ISO-8601
  kind            TEXT NOT NULL,              -- 'youtube' | 'files' | 'mixed'
  expected_count  INTEGER NOT NULL,           -- Fixed at creation
  state           TEXT NOT NULL,              -- active | assembling | completed | completedWithErrors | cancelled
  language        TEXT,                       -- NULL = auto
  output_path     TEXT,
  cleaned_at      TEXT
);

CREATE TABLE job (
  id              TEXT PRIMARY KEY,           -- UUID
  batch_id        TEXT NOT NULL REFERENCES batch(id) ON DELETE CASCADE,
  sequence        INTEGER NOT NULL,           -- 1..N sequence observed by user
  source_type     TEXT NOT NULL,              -- youtube | localFile | watchedFolder
  source_url      TEXT,
  source_path     TEXT,
  external_id     TEXT,                       -- YouTube video ID or unique hash
  title           TEXT,
  creator         TEXT,
  duration_sec    REAL,
  state           TEXT NOT NULL,
  attempt         INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TEXT,
  error_kind      TEXT,
  error_message   TEXT,
  workspace_path  TEXT,
  detected_lang   TEXT,
  updated_at      TEXT NOT NULL,
  UNIQUE(batch_id, sequence),
  UNIQUE(batch_id, external_id)
);

CREATE TABLE transcript_section (
  job_id     TEXT PRIMARY KEY REFERENCES job(id) ON DELETE CASCADE,
  text       TEXT NOT NULL,                   -- Post-processed paragraph text
  segments   TEXT                             -- JSON serialized segments with timestamps
);

CREATE TABLE transcript_cache (
  id              TEXT PRIMARY KEY,
  external_id     TEXT,
  title           TEXT NOT NULL,
  duration_sec    REAL,
  text            TEXT NOT NULL,
  segments_json   TEXT,
  detected_lang   TEXT,
  created_at      TEXT NOT NULL
);

CREATE TABLE session_item (
  id          TEXT PRIMARY KEY,
  position    INTEGER NOT NULL,
  url         TEXT NOT NULL,
  external_id TEXT NOT NULL UNIQUE,
  title       TEXT,
  duration_sec REAL,
  added_at    TEXT NOT NULL
);

CREATE TABLE history (
  external_id TEXT PRIMARY KEY,
  title       TEXT,
  output_path TEXT,
  done_at     TEXT NOT NULL
);

CREATE TABLE watched_folder (
  id TEXT PRIMARY KEY, path TEXT NOT NULL UNIQUE, enabled INTEGER NOT NULL,
  extensions TEXT NOT NULL, delete_original INTEGER NOT NULL DEFAULT 0
);
```

---

### 6. Job State Machine

Lifecycle states: `queued → fetching → fetched → transcribing → transcribed → completed`; error paths: `retryWaiting`, `failed`; user intervention: `cancelled`.

Rules:
- State transitions are executed exclusively within the `JobManager` actor inside SQLite database transactions. Invalid transitions raise assertions and error logs.
- `fetched`: media file verified in local workspace. `transcribed`: `transcript_section` committed to SQLite.
- Terminal states: `completed`, `failed`, `cancelled`.
- When all jobs within a batch reach terminal states, the batch transitions to `assembling` → output written to disk → `completed` (if 0 failures) or `completedWithErrors`.

Crash Recovery:
- `fetching` → workspace partial files removed, reset to `queued`.
- `fetched` → retained as-is (never re-downloaded).
- `transcribing` → reset to `fetched` (re-transcribed from scratch).
- `transcribed` → retained as-is.
- `assembling` batch → re-assembled.
- Unreferenced workspace folders and `.partial` files are purged.

---

### 7. Pipeline and Concurrency

```
[queued] --(FetchQueue: max 2 concurrent YouTube / 4 local)--> [fetched]
[fetched] --(TranscribeQueue: strictly 1 at a time on Metal GPU)--> [transcribed]
All jobs terminal --> BatchAssembler --> OutputWriter --> CleanupManager
```

- Ingestion and transcription run asynchronously: video 1 transcribes while videos 2–3 download in parallel.
- Transcription queue order: ascending `sequence`, FIFO across batches.
- Single Whisper context instance maintained on Metal GPU during batch runs; freed after 10 minutes of inactivity.
- YouTube network calls include randomized 1–3s jitter intervals.

---

### 8. Module Specifications

#### 8.1 URLParser
- Uses `URLComponents` parsing (not brittle regex). Valid hosts: `youtube.com`, `www.youtube.com`, `m.youtube.com`, `music.youtube.com`, `youtu.be`, `www.youtube-nocookie.com`.
- Recognized paths: `/watch?v=ID`, `youtu.be/ID`, `/shorts/ID`, `/live/ID`, `/embed/ID`. ID must match exactly 11 characters `[A-Za-z0-9_-]`.
- Extracts multiple URLs from arbitrary text bodies (bulk paste).
- Canonical URL format: `https://www.youtube.com/watch?v=ID`.

#### 8.2 ClipboardMonitor
- Runs on a 0.75s polling timer tracking `NSPasteboard.general.changeCount`.
- Ignores entries containing `org.nspasteboard.ConcealedType` or `org.nspasteboard.TransientType` (protecting password managers).
- Resolves lightweight video metadata asynchronously and adds entries to the queue.

#### 8.3 ToolManager
- Manages standalone `yt-dlp` and `Deno` binaries under `~/Library/Application Support/<bundle-id>/Tools/`.
- Verifies SHA-256 checksums against official upstream release manifests before deployment.
- Calls `yt-dlp` with `--js-runtimes deno:<path>`.
- Auto-updates tools on extraction failures (`extractorError`, HTTP 403) if not checked within 6 hours.

#### 8.4 YTDLPClient (YouTube Audio Ingestion)
- Executes command:
  ```bash
  yt-dlp --no-playlist --newline --socket-timeout 30 --retries 3 \
    -f "bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/18" \
    -o "<workspace>/input.%(ext)s" \
    --no-simulate --print "%(.{id,title,channel,duration,ext})#j" \
    --progress --progress-template "download:%(progress._percent_str)s" \
    --js-runtimes deno:<deno_path> <url>
  ```
- Parses JSON metadata and progress percentage strings from standard output.
- Classifies errors into structured categories: `videoUnavailable`, `ageRestricted`, `botCheck`, `network`, `noAudioFormat`, `unknown`.

#### 8.5 LocalFileAdapter & FolderWatcher
- Uses APFS `clonefile` for instantaneous, zero-copy local file ingestion.
- `FolderWatcher` monitors via `FSEventStreamCreate` and scans on launch.
- Handles iCloud dataless placeholder files (`.icloud`) via `FileManager.startDownloadingUbiquitousItem(at:)`.
- Validates file stability across 3-second measurement windows.

#### 8.6 AudioDecoder
- Uses `AVAudioFile` and `AVAudioConverter` to convert arbitrary audio containers into 16 kHz mono Float32 PCM arrays.
- Splits recordings longer than 3 hours into 30-minute processing chunks with time-offset aggregation.

#### 8.7 WhisperCppEngine
- Initialized with `whisper_init_from_file_with_params` (Metal GPU enabled).
- Utilizes Silero VAD v6.2.0 for precise silence suppression.
- Reports real-time token progress via `progress_callback` and streaming decoded segments to the UI.

#### 8.8 TranscriptPostProcessor
- Cleans whitespace and strips hallucinated noise tags (`[BLANK_AUDIO]`, `[Music]`, `(applause)`).
- Repetition loop break: detects identical consecutive segment repeats ($\ge 3$ iterations) and suppresses hallucinations.
- Paragraph formatting: breaks into structured paragraphs based on $\ge 1.5$s silence boundaries or ~600 character sentence thresholds.

#### 8.9 OutputWriter & Format-Version 1
- Writes output atomically: creates `.<filename>.partial`, flushes via `FileHandle.synchronize()`, validates UTF-8 content, and atomically renames.
- Filename sanitization: replaces invalid characters (`/ : \ * ? " < > |`) with hyphens, trims whitespace, limits length to 150 graphemes.
- Non-destructive collision handling: appends `(2)`, `(3)` if target filename exists. Never overwrites user files.

---

### 9. Output Format Specification (Format-Version 1)

```
TRANSKRIPT HUB EXPORT
Format-Version: 1
Batch-ID: 2C5E…-UUID
Source-Type: YouTube
Created: 2026-10-03 21:03:02
Item-Count: 5
Completed: 4
Failed: 1
Model: large-v3-turbo (f16), VAD: on, Language: auto

====================================================================
VIDEO 1 / 5
====================================================================
TITLE: Machine Learning Lecture 1
CHANNEL: Stanford Online
DURATION: 15:14
URL: https://www.youtube.com/watch?v=…
LANGUAGE: en

TRANSCRIPT

<Formatted paragraphs separated by blank lines>

====================================================================
VIDEO 2 / 5
====================================================================
TITLE: Private Research Briefing
URL: https://www.youtube.com/watch?v=…
STATUS: FAILED — Video unavailable (deleted or private)
```

---

### 10. Privacy & Security Guarantees

- Zero audio, video, or transcript data is ever transmitted to external servers.
- Network activity is strictly limited to: YouTube stream extraction, official Whisper model downloads, and tool updates.
- No analytics, tracking, or telemetry SDKs.
- Transcript text is never written to application diagnostic logs.
