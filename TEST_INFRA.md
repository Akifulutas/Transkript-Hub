# Transkript Hub — Test Infrastructure & 4-Tier Test Suite Specification

## 1. Test Infrastructure Overview

Transkript Hub employs an Apple 1st-Party quality, privacy-first, requirement-driven opaque-box testing framework. The test infrastructure strictly enforces Apple's modern Swift 6 Concurrency model, utilizes native frameworks (`Testing`, `XCTest`, `AVFoundation`, `Accelerate/vDSP`, `GRDB.swift`, `NaturalLanguage`), and ensures zero regressions against all existing baseline capabilities while guaranteeing performance, stability, and data integrity.

### 1.1 Methodology: 4-Tier Test Design
The test suite is structured around a 4-Tier hierarchical methodology:
- **Tier 1: Feature Coverage (>=5 test cases per feature across all 22 features, >=110 test cases)**
  Validates standard nominal execution (happy paths) and functional contracts for every feature in `PROJECT.md`.
- **Tier 2: Boundary & Corner Cases (>=5 test cases per feature across all 22 features, >=110 test cases)**
  Validates system resilience against extreme values, zero-lengths, clipping, concurrency races, malformed inputs, and edge conditions.
- **Tier 3: Cross-Feature Combinations (Pairwise & Multi-Feature Interactions)**
  Validates component boundary contracts, data handoffs, and feedback loops across multiple features executing concurrently.
- **Tier 4: Real-World Application Scenarios (Realistic End-to-End User Workflows)**
  Simulates full real-world user workflows from microphone or URL ingestion to final exported, atomically synchronized transcript models.

---

## 2. Tier 1: Feature Coverage (5 Test Cases per Feature across 22 Features)

### FEAT-R1-01: Token Timestamps Extraction
*Source: M1 / R1.1, Survey*
- **TC-T1-R101-01: Word-level Millisecond Extraction**
  - *Input*: 5-second PCM audio buffer containing clear speech ("Merhaba dünya").
  - *Expected Output*: Extracted segments containing word tokens where each `Word` has `start < end`, `confidence > 0.0`, and non-empty `text`.
  - *Verification*: Token array count matches spoken word count; millisecond boundaries monotonically increase.
- **TC-T1-R101-02: Whisper Token Flag Enforcement**
  - *Input*: Transcription options with `token_timestamps = true`.
  - *Expected Output*: Engine produces token data structure via `whisper_full_get_token_data`.
  - *Verification*: Non-empty token array returned alongside segment texts.
- **TC-T1-R101-03: Multi-Segment Sequential Token Ordering**
  - *Input*: Multi-sentence speech spanning 3 distinct segments.
  - *Expected Output*: Last token of segment $N$ ends before or at the start token of segment $N+1$.
  - *Verification*: Assert `segments[n].words.last!.end <= segments[n+1].words.first!.start + 0.05`.
- **TC-T1-R101-04: Confidence Score Propagation**
  - *Input*: Audio segment with clear audio vs noisy audio.
  - *Expected Output*: Token confidence scores accurately reflect acoustic probability ($0.0 \le \text{confidence} \le 1.0$).
  - *Verification*: High SNR words yield confidence $\ge 0.70$.
- **TC-T1-R101-05: Punctuation and Token Association**
  - *Input*: Spoken utterance terminating with a question mark.
  - *Expected Output*: Punctuation is properly attached to word token without corrupting timestamp window.
  - *Verification*: `word.text` equals "dünya?" with valid start and end timestamps.

### FEAT-R1-02: Native Audio Player Controller
*Source: M1 / R1.1, AC#1, Survey*
- **TC-T1-R102-01: Audio Playback Lifecycle State Transitions**
  - *Input*: Load `sample.m4a`, issue `play()`, wait 500ms, issue `pause()`.
  - *Expected Output*: `isPlaying` transitions from `false` to `true`, then back to `false`; `currentTime` advances.
  - *Verification*: Observer notifications fire with expected state updates.
- **TC-T1-R102-02: Seek Target Accuracy (±100ms tolerance)**
  - *Input*: Audio loaded (duration > 5.0s), seek command to $t = 2.500$s.
  - *Expected Output*: Playhead updates to $2.500 \pm 0.100$s.
  - *Verification*: Assert `abs(controller.currentTime - 2.5) <= 0.100`.
- **TC-T1-R102-03: Toggle Play/Pause Ergonomics**
  - *Input*: Single invoke of `togglePlayPause()` when paused, followed by a second invoke.
  - *Expected Output*: State alternates: `paused -> playing -> paused`.
  - *Verification*: Verify `isPlaying == true`, then `isPlaying == false`.
- **TC-T1-R102-04: Duration Reporting Fidelity**
  - *Input*: Load valid audio sample file.
  - *Expected Output*: Controller reports audio duration matching `AudioValidator` duration within 10ms.
  - *Verification*: Assert `abs(controller.duration - validatorDuration) < 0.01`.
- **TC-T1-R102-05: Continuous Playhead Periodic Observation**
  - *Input*: Playback for 300ms with periodic observer installed at 50ms intervals.
  - *Expected Output*: Periodic observer callback fires at least 5 times with monotonically increasing time.
  - *Verification*: Captured time values satisfy $t_{i} < t_{i+1}$.

### FEAT-R1-03: Accelerate/vDSP Waveform Generator
*Source: M1 / R1.2, R6.2, Survey*
- **TC-T1-R103-01: Normalized Envelope Bar Generation**
  - *Input*: 10-second 16kHz audio buffer, target points = 100.
  - *Expected Output*: Exactly 100 `WaveformPoint` items where $0.0 \le \text{min} \le \text{max} \le 1.0$.
  - *Verification*: Array length is 100; all point values lie in $[0.0, 1.0]$.
- **TC-T1-R103-02: vDSP Performance Budget (<15ms latency)**
  - *Input*: 60-second audio stream (960,000 float samples), target points = 500.
  - *Expected Output*: Waveform point calculation completes in $< 15.0$ ms.
  - *Verification*: Measure elapsed time using `ContinuousClock`. Assert `elapsed < .milliseconds(15)`.
- **TC-T1-R103-03: Peak vs RMS Downsampling Consistency**
  - *Input*: Synthetic sine wave with amplitude 0.8.
  - *Expected Output*: Peak envelope captures maximum magnitude 0.8, RMS captures $0.8 / \sqrt{2} \approx 0.565$.
  - *Verification*: Envelope max values match expected mathematical derivation within 2%.
- **TC-T1-R103-04: Dynamic Target Point Scaling**
  - *Input*: Request waveforms with target points = 50, 200, 1000.
  - *Expected Output*: Returned points count strictly matches requested target points for each call.
  - *Verification*: `points.count == targetPoints`.
- **TC-T1-R103-05: Waveform Generator Protocol Conformance**
  - *Input*: Instance conforming to `WaveformGenerating`.
  - *Expected Output*: Conforms to `Sendable` and handles concurrent invocation safely.
  - *Verification*: Concurrent calls across 4 Swift tasks succeed without data races.

### FEAT-R1-04: Interactive Waveform Visualizer
*Source: M1 / R1.2, AC#2, Survey*
- **TC-T1-R104-01: Click-to-Seek Coordinate Mapping**
  - *Input*: Waveform view width = 1000px, duration = 100s, click event at $x = 250$px.
  - *Expected Output*: Playhead seeks to $t = 25.0$s.
  - *Verification*: Calculated seek target is $25.0 \pm 0.1$s.
- **TC-T1-R104-02: Scrubbing Playhead Synchrony**
  - *Input*: User drags scrub handle continuously from $x = 100$px to $x = 500$px.
  - *Expected Output*: Intermediate scrub positions stream without dropped frames or jumpy UI.
  - *Verification*: Scrubbing updates playhead position smoothly across normalized range $[0.10, 0.50]$.
- **TC-T1-R104-03: Playback Progress Bar Indicator**
  - *Input*: Current time is 30s of 60s total duration.
  - *Expected Output*: Progress fraction is exactly 0.50.
  - *Verification*: Visualizer progress ratio == 0.50.
- **TC-T1-R104-04: 60/120fps Display Link Update Cycle**
  - *Input*: Waveform rendering under continuous playback.
  - *Expected Output*: Frame render execution completes within 8.3ms (120fps budget) on Apple Silicon.
  - *Verification*: Execution time per frame is $< 8.3$ ms.
- **TC-T1-R104-05: Color Palette / Vibrancy Theming**
  - *Input*: Waveform visualizer rendered in light mode and dark mode.
  - *Expected Output*: Foreground played bars use Apple accent color, unplayed bars use secondary subtle fill.
  - *Verification*: Visual hierarchy maintained with contrast ratio $\ge 4.5:1$.

### FEAT-R1-05: Karaoke Synchronized Transcript
*Source: M1 / R1.3, AC#1, Survey*
- **TC-T1-R105-01: Active Word Illumination by Timestamp**
  - *Input*: Words with timestamps [w1: 0.0-1.0s, w2: 1.0-2.0s, w3: 2.0-3.0s]. Current time = 1.5s.
  - *Expected Output*: Word w2 is active/highlighted; w1 and w3 are inactive.
  - *Verification*: Active word index query returns 1.
- **TC-T1-R105-02: Word Click-to-Seek Action**
  - *Input*: User clicks word w3 (start: 2.0s).
  - *Expected Output*: Controller receives seek target $2.0$s; playback time jumps to $2.0 \pm 0.1$s.
  - *Verification*: `controller.currentTime` lands at 2.0s.
- **TC-T1-R105-03: Fast Interval Binary Search Efficiency**
  - *Input*: Transcript containing 10,000 words; search for word at current time $t = 345.2$s.
  - *Expected Output*: Correct word index found in $O(\log N)$ time ($< 0.05$ms).
  - *Verification*: Retrieved word interval encompasses 345.2s.
- **TC-T1-R105-04: Inter-Word Silence Handling**
  - *Input*: Word w1 ends at 1.0s, word w2 starts at 2.0s. Current time = 1.5s (pause).
  - *Expected Output*: Active highlight holds previous word or rests cleanly without erroneous selection.
  - *Verification*: State handles gap without out-of-bounds error.
- **TC-T1-R105-05: Auto-Scroll to Active Word**
  - *Input*: Playhead advances past current viewport boundary into paragraph 3.
  - *Expected Output*: Scroll target updates to bring active word into vertical viewport.
  - *Verification*: Target scroll index matches active word segment index.

### FEAT-R1-06: Audio Session Media Retention
*Source: M1 / R1.1, Caveats, Survey*
- **TC-T1-R106-01: Session Storage Preservation**
  - *Input*: Audio file downloaded or imported into session workspace.
  - *Expected Output*: Audio file remains intact on disk across player pause/resume cycles.
  - *Verification*: File exists at `workspacePath` and size is $> 0$.
- **TC-T1-R106-02: Retained Media Playback Re-Arming**
  - *Input*: Finish playing track; user clicks restart or seek to 0.
  - *Expected Output*: Audio session re-arms from retained file without requiring re-download or re-conversion.
  - *Verification*: Playback resumes immediately from $t = 0$.
- **TC-T1-R106-03: Temporary File Cleanliness on Batch Assembly**
  - *Input*: Session cleanup triggered for completed batch.
  - *Expected Output*: Retained audio is purged only when user explicitly confirms or batch lifecycle terminates.
  - *Verification*: Verify lifecycle hook triggers cleanup only upon final state.
- **TC-T1-R106-04: Session Cache Lookup by Hash/URL**
  - *Input*: Audio URL previously ingested in active session.
  - *Expected Output*: Media loader retrieves cached local file path instead of refetching.
  - *Verification*: Local path matches previously saved workspace file.
- **TC-T1-R106-05: File Integrity Verification on Re-Open**
  - *Input*: Retained media file loaded after app backgrounding.
  - *Expected Output*: File header is verified via `AudioValidator` before playback initialization.
  - *Verification*: Validation passes without error.

### FEAT-R2-01: Audio & Mic Recording Engine
*Source: M2 / R2.1, AC#4, Survey*
- **TC-T1-R201-01: Recording Lifecycle (Start/Stop)**
  - *Input*: Invoke `startRecording()`, record for 1.0s, invoke `stopRecording()`.
  - *Expected Output*: Returns valid output file URL; `isRecording` transitions `false -> true -> false`.
  - *Verification*: File exists, size $> 0$, readable by `AVAudioFile`.
- **TC-T1-R201-02: Format Compliance (AAC/LPCM m4a)**
  - *Input*: Recorded audio file produced by engine.
  - *Expected Output*: Format is 16kHz or 44.1kHz AAC/LPCM m4a.
  - *Verification*: Inspect `AVAudioFile.fileFormat`; verify sample rate and channel count (1 or 2).
- **TC-T1-R201-03: Input Node Tap Buffer Acquisition**
  - *Input*: Audio engine running during recording.
  - *Expected Output*: Real-time PCM buffer tap captures continuous non-empty buffers.
  - *Verification*: Buffer tap callback receives `AVAudioPCMBuffer` with `frameLength > 0`.
- **TC-T1-R201-04: Pause and Resume Recording**
  - *Input*: Start recording, pause for 500ms, resume for 500ms, stop.
  - *Expected Output*: Recorded file contains concatenated audio of both active intervals (~1.0s duration).
  - *Verification*: Recorded file duration matches active elapsed time ($1.0 \pm 0.2$s).
- **TC-T1-R201-05: Clean Cancellation Discard**
  - *Input*: Start recording, invoke `cancelRecording()`.
  - *Expected Output*: Recording stops; temporary partial file is cleanly deleted from disk.
  - *Verification*: `FileManager.default.fileExists` returns `false` for temporary file.

### FEAT-R2-02: Real-Time Audio Level Metering
*Source: M2 / R2.2, AC#5, Survey*
- **TC-T1-R202-01: RMS Decibel Calculation**
  - *Input*: PCM audio buffer containing full-scale sine wave (amplitude 1.0).
  - *Expected Output*: Metering level is calculated close to $1.0$ (0 dBFS).
  - *Verification*: Assert `abs(currentMeteringLevel - 1.0) < 0.05`.
- **TC-T1-R202-02: Digital Silence Metering Floor**
  - *Input*: PCM audio buffer containing all zero samples.
  - *Expected Output*: Metering level reports $0.0$ (-60 dBFS or lower floor).
  - *Verification*: Assert `currentMeteringLevel == 0.0`.
- **TC-T1-R202-03: Normalized Level Clamping [0.0, 1.0]**
  - *Input*: Input signal varying from quiet whisper to loud shout.
  - *Expected Output*: Output level is strictly bounded within $[0.0, 1.0]$.
  - *Verification*: Assert `0.0 <= level && level <= 1.0` across 1,000 continuous frames.
- **TC-T1-R202-04: vDSP Frequency Band FFT Decomposition**
  - *Input*: 1kHz pure tone buffer fed to analyzer.
  - *Expected Output*: Frequency band corresponding to 1kHz displays dominant energy peak relative to other bands.
  - *Verification*: `frequencyBands[k]` has significantly higher magnitude than surrounding bands.
- **TC-T1-R202-05: Metering Response Time (<20ms)**
  - *Input*: Transient audio pulse introduced into stream.
  - *Expected Output*: Metering level updates within next metering frame ($< 20$ ms).
  - *Verification*: Level rise detected in immediately following callback.

### FEAT-R2-03: Live Frequency Bar Visualizer
*Source: M2 / R2.3, AC#5, Survey*
- **TC-T1-R203-01: Bar Height Proportionality**
  - *Input*: Meter level array `[0.2, 0.5, 0.8]`.
  - *Expected Output*: Rendered bar heights scale proportionally to input values.
  - *Verification*: Visual height ratio matches input values.
- **TC-T1-R203-02: Smooth Attack/Decay Animation**
  - *Input*: Sudden drop of input level from 0.9 to 0.0.
  - *Expected Output*: Visual bars animate downward with exponential decay rather than instantaneous drop.
  - *Verification*: Intermediate frames show decaying values ($v_{t} > v_{t+1} > 0.0$).
- **TC-T1-R203-03: Peak Hold Indicator**
  - *Input*: Loud audio transient followed by silence.
  - *Expected Output*: Peak tick remains at maximum level for preset hold time (e.g. 500ms) before fading.
  - *Verification*: Peak indicator persists during hold window.
- **TC-T1-R203-04: 16-Band Equalizer Layout**
  - *Input*: 16 frequency band values supplied by recording engine.
  - *Expected Output*: Visualizer renders exactly 16 distinct vertical frequency bars with equal spacing.
  - *Verification*: Render hierarchy contains 16 bar elements.
- **TC-T1-R203-05: Inactive State Idle Waveform**
  - *Input*: Engine is idle (`isRecording == false`).
  - *Expected Output*: Visualizer displays gentle idle breathing wave or flat baseline without CPU burn.
  - *Verification*: CPU usage in idle view state is $< 1\%$.

### FEAT-R2-04: Instant Auto-Transcribe & Auto-Save
*Source: M2 / R2.3, AC#4, Survey*
- **TC-T1-R204-01: Seamless Recording-to-Job Pipeline**
  - *Input*: User stops recording.
  - *Expected Output*: Recorded file is automatically enqueued into `JobManager` with state `.queued`.
  - *Verification*: New `JobRecord` is created in database referencing recorded file path.
- **TC-T1-R204-02: Auto-Save to User History**
  - *Input*: Recording finishes transcription.
  - *Expected Output*: Transcript record inserted into `HistoryRecord` with timestamp and title.
  - *Verification*: Query `history` table; record exists with matching external ID.
- **TC-T1-R204-03: Auto-Export to Designated Export Folder**
  - *Input*: User has configured export directory in settings.
  - *Expected Output*: Formatted transcript file (txt or srt) is written automatically to export folder.
  - *Verification*: File exists at export path with non-empty content.
- **TC-T1-R204-04: Default Title Generation with Timestamp**
  - *Input*: Recorded clip created without explicit user title.
  - *Expected Output*: Title defaults to "Kayıt YYYY-MM-DD HH:mm:ss" or similar timestamp format.
  - *Verification*: Title string matches timestamp pattern.
- **TC-T1-R204-05: Non-Blocking Background Execution**
  - *Input*: Auto-transcription triggered upon recording stop.
  - *Expected Output*: UI remains interactive; transcription runs asynchronously in background task.
  - *Verification*: Main thread is not blocked; UI responds immediately.

### FEAT-R2-05: Recording Entitlements & Privacy
*Source: M2 / R2.1, Caveats, Survey*
- **TC-T1-R205-01: Info.plist Microphone Usage Description**
  - *Input*: App bundle `Info.plist`.
  - *Expected Output*: Contains non-empty `NSMicrophoneUsageDescription` key explaining purpose.
  - *Verification*: Assert `bundle.infoDictionary?["NSMicrophoneUsageDescription"] != nil`.
- **TC-T1-R205-02: Hardware Entitlement Presence**
  - *Input*: App entitlements file.
  - *Expected Output*: `com.apple.security.device.audio-input` is set to `true`.
  - *Verification*: Entitlements dictionary includes audio-input capability.
- **TC-T1-R205-03: Permission Authorization State Check**
  - *Input*: Query microphone authorization status via `AVCaptureDevice`.
  - *Expected Output*: Engine checks `.authorized`, `.denied`, or `.notDetermined` before tapping input.
  - *Verification*: Proper permission workflow invoked.
- **TC-T1-R205-04: Graceful Permission Denial Error Handling**
  - *Input*: User denies microphone permission.
  - *Expected Output*: `startRecording()` throws explicit typed error `permissionDenied` without crash.
  - *Verification*: Catch `permissionDenied` error and display user-facing settings link.
- **TC-T1-R205-05: Privacy Indicator Orange Dot Compliance**
  - *Input*: Audio recording engine stops.
  - *Expected Output*: Input tap is removed and audio engine stopped immediately, extinguishing macOS orange dot.
  - *Verification*: Engine is not running when stopped.

### FEAT-R3-01: Acoustic Turn Diarization
*Source: M3 / R3.1, AC#6, Survey*
- **TC-T1-R301-01: Silence Boundary Speaker Turn Detection**
  - *Input*: Segments with 1.2s pause between segment 2 and segment 3.
  - *Expected Output*: Segments 1-2 assigned to Speaker 1, segments 3-4 assigned to Speaker 2.
  - *Verification*: `segment2.speaker != segment3.speaker`.
- **TC-T1-R301-02: Continuous Speech Single Speaker Turn**
  - *Input*: Segments separated by short pauses ($< 0.4$s).
  - *Expected Output*: Segments remain grouped under the same speaker ID.
  - *Verification*: `segment1.speaker == segment2.speaker`.
- **TC-T1-R301-03: Speaker Turn Clustering Consistency**
  - *Input*: Two alternating speakers across 8 conversational turns.
  - *Expected Output*: Alternating segments assigned to consistent IDs ("Speaker 1" and "Speaker 2").
  - *Verification*: Distinct speaker count in transcript equals 2.
- **TC-T1-R301-04: Diarization Energy/Pause Profiling via vDSP**
  - *Input*: Audio track containing alternating voices with distinct pitch/energy profiles.
  - *Expected Output*: Turn boundaries correspond to acoustic feature transition points.
  - *Verification*: Boundary indices align with acoustic changes.
- **TC-T1-R301-05: Default Fallback for Monologues**
  - *Input*: 5-minute single-speaker lecture with no major voice change.
  - *Expected Output*: All segments assigned to "Speaker 1".
  - *Verification*: Unique speaker set contains exactly 1 element.

### FEAT-R3-02: Colored Speaker Badges & Rename
*Source: M3 / R3.1, AC#6, Survey*
- **TC-T1-R302-01: Distinct Apple HIG Palette Mapping**
  - *Input*: Speakers ["Speaker 1", "Speaker 2", "Speaker 3"].
  - *Expected Output*: Each speaker assigned a distinct, deterministic Apple HIG color (e.g., Blue, Purple, Orange).
  - *Verification*: Color assignments are unique across different speaker IDs.
- **TC-T1-R302-02: Deterministic Color Stability**
  - *Input*: Re-rendering transcript multiple times.
  - *Expected Output*: "Speaker 1" consistently receives the identical color badge.
  - *Verification*: Badge color for "Speaker 1" is invariant across view updates.
- **TC-T1-R302-03: Inline Speaker Renaming Propagation**
  - *Input*: Rename "Speaker 1" to "Ahmet Bey".
  - *Expected Output*: All segments formerly labeled "Speaker 1" update their speaker name to "Ahmet Bey".
  - *Verification*: Segments with speaker "Speaker 1" are updated; "Speaker 2" segments remain unchanged.
- **TC-T1-R302-04: Badge Contrast in Dark & Light Mode**
  - *Input*: Speaker badge rendered on liquid glass background.
  - *Expected Output*: Badge text and background adhere to Apple accessibility contrast requirements.
  - *Verification*: Text color provides readable contrast over badge tint.
- **TC-T1-R302-05: Custom Speaker Name Persistence**
  - *Input*: Transcript saved after speaker rename.
  - *Expected Output*: Renamed speaker tag persists in database model and JSON segments.
  - *Verification*: Reloading transcript displays custom name.

### FEAT-R3-03: Inline Rich Transcript Editor
*Source: M3 / R3.2, AC#7, Survey*
- **TC-T1-R303-01: Direct In-Place Text Editing**
  - *Input*: User modifies a misspelled word in segment 2 from "teşekkür" to "teşekkürler".
  - *Expected Output*: Segment text updates in-memory immediately without needing export/re-import.
  - *Verification*: `segment.text` contains updated string.
- **TC-T1-R303-02: Word Timestamp Preservation During Text Edit**
  - *Input*: User modifies word text while leaving start and end timestamps intact.
  - *Expected Output*: Segment start/end and other word timestamps remain intact.
  - *Verification*: `segment.start` and `segment.end` are unaltered.
- **TC-T1-R303-03: Undo / Redo Operations Support**
  - *Input*: Perform text edit, invoke `undo()`, then invoke `redo()`.
  - *Expected Output*: Text reverts to original on undo, and restores edited string on redo.
  - *Verification*: Text state reflects undo and redo stages accurately.
- **TC-T1-R303-04: Segment Split on Return Key**
  - *Input*: User presses Enter in the middle of a segment sentence.
  - *Expected Output*: Segment splits into two valid segments with apportioned text and timestamps.
  - *Verification*: Segment count increases by 1; total text matches original.
- **TC-T1-R303-05: Segment Merge on Backspace**
  - *Input*: User presses Backspace at the start of segment $N+1$.
  - *Expected Output*: Segment $N+1$ merges into segment $N$, combining text and spanning from $N.\text{start}$ to $N+1.\text{end}$.
  - *Verification*: Segment count decreases by 1; merged segment span is valid.

### FEAT-R3-04: Atomic Database Model Sync
*Source: M3 / R3.2, AC#7, Survey*
- **TC-T1-R304-01: Atomic Transcript Section Update**
  - *Input*: Invoke `updateTranscript(jobId: "job-1", newText: "...", segments: [...])`.
  - *Expected Output*: Database updates `transcript_section` in a single SQLite transaction.
  - *Verification*: Reading `transcript_section` returns exactly the new text and serialized segments.
- **TC-T1-R304-02: Rollback on Database Error**
  - *Input*: Simulate transaction failure (e.g. foreign key constraint violation or disk full).
  - *Expected Output*: Transaction rolls back; original transcript remains completely unchanged.
  - *Verification*: Database content matches state before attempted update.
- **TC-T1-R304-03: Concurrent Read While Updating (WAL Mode)**
  - *Input*: Background task performs continuous read queries while an update is writing.
  - *Expected Output*: Readers never observe partial or corrupt states; SQLite WAL mode ensures clean isolation.
  - *Verification*: All read queries return either previous consistent state or new consistent state.
- **TC-T1-R304-04: JSON Segment Serialization Round-Trip**
  - *Input*: Segments with nested `Word` structures, speaker tags, and special characters.
  - *Expected Output*: Segments serialized to JSON string in database and deserialized back without data loss.
  - *Verification*: Deserialized segments equal original segments (`#expect(deserialized == original)`).
- **TC-T1-R304-05: Cascade Delete Safety**
  - *Input*: Delete parent `BatchRecord` or `JobRecord`.
  - *Expected Output*: Associated `transcript_section` is deleted via foreign key cascade without orphaned rows.
  - *Verification*: Querying `transcript_section` for deleted `job_id` returns nil.

### FEAT-R3-05: Local Summary & Chaptering
*Source: M3 / R3.3, Survey*
- **TC-T1-R305-01: Local Apple NaturalLanguage Extractive Summarization**
  - *Input*: 2000-word transcript.
  - *Expected Output*: Generates 3-5 key sentence extractive summary without sending data to external APIs.
  - *Verification*: Summary contains key sentences directly from source text; zero network calls made.
- **TC-T1-R305-02: Action Items Extraction**
  - *Input*: Transcript containing imperative action statements ("Görevleri yarına kadar tamamlayalım").
  - *Expected Output*: Bulleted action item list extracted based on linguistic cue parsing.
  - *Verification*: Extracted items list includes the action statement.
- **TC-T1-R305-03: Timestamped Chapter Generation**
  - *Input*: 30-minute podcast transcript with topic transitions.
  - *Expected Output*: 3 to 6 timestamped chapters with titles and start times.
  - *Verification*: Chapter start times monotonically increase ($t_1 < t_2 < t_3$).
- **TC-T1-R305-04: Chapter Click-to-Seek Integration**
  - *Input*: User clicks on Chapter 2 (timestamp: 12:45).
  - *Expected Output*: Player controller seeks to $765.0$ seconds ($12 \times 60 + 45$).
  - *Verification*: Controller seeks to chapter start time.
- **TC-T1-R305-05: Zero Cloud Leakage Compliance**
  - *Input*: Summarization pipeline execution.
  - *Expected Output*: NaturalLanguage processing executes 100% on-device on Apple Neural Engine / CPU.
  - *Verification*: Process makes zero outbound sockets or HTTP requests.

### FEAT-R4-01: Menu Bar Drag-and-Drop Extra
*Source: M4 / R4.1, Survey*
- **TC-T1-R401-01: NSStatusItem Initialization and Presence**
  - *Input*: App launch in Menu Bar mode.
  - *Expected Output*: Status item icon is visible in macOS menu bar with SF Symbol.
  - *Verification*: `NSStatusBar.system.statusItem` exists.
- **TC-T1-R401-02: Audio File Drag-and-Drop Ingestion**
  - *Input*: Drag `sample.m4a` file from Finder onto Menu Bar item.
  - *Expected Output*: File drop accepted; new job automatically initialized for `sample.m4a`.
  - *Verification*: Job queue increments by 1 with source path matching dropped file.
- **TC-T1-R401-03: YouTube URL String Paste Ingestion**
  - *Input*: Paste "https://www.youtube.com/watch?v=dQw4w9WgXcQ" into Menu Bar drop zone.
  - *Expected Output*: URL recognized, validated via `URLParser`, and added to session queue.
  - *Verification*: `QueueItem` created with parsed external ID.
- **TC-T1-R401-04: Mini Popover Window Toggle**
  - *Input*: Click on Menu Bar icon.
  - *Expected Output*: Mini popover window opens anchored to status item; clicking outside dismisses it.
  - *Verification*: Popover `isShown` transitions `false -> true -> false`.
- **TC-T1-R401-05: Headless Mini Progress Display**
  - *Input*: Active transcription job in progress.
  - *Expected Output*: Menu Bar icon or popover displays circular progress indicator or percentage.
  - *Verification*: Progress value reflects current batch progress ($0.0 \dots 1.0$).

### FEAT-R4-02: Floating Drop-Zone & Quick Dictation
*Source: M4 / R4.2, Survey*
- **TC-T1-R402-01: Floating Drop-Zone Always-on-Top Window**
  - *Input*: User enables floating drop zone.
  - *Expected Output*: Floating panel appears with `.floating` window level, staying above other apps.
  - *Verification*: Window level equals `NSWindow.Level.floating`.
- **TC-T1-R402-02: Quick Dictation Global Hotkey Trigger**
  - *Input*: Press registered global hotkey (e.g. ⌥Space or ⌘⌥R).
  - *Expected Output*: Direct microphone recording engine activates immediately without activating main window.
  - *Verification*: `AudioRecordingEngine.isRecording == true`.
- **TC-T1-R402-03: Quick Dictation Auto-Stop and Transcribe**
  - *Input*: Release hotkey or press hotkey second time.
  - *Expected Output*: Recording stops, audio is transcribed instantly, and text is copied to clipboard.
  - *Verification*: `NSPasteboard.general` contains transcribed text.
- **TC-T1-R402-04: Multi-File Drag-and-Drop Batching**
  - *Input*: Drag 5 audio files simultaneously onto floating drop zone.
  - *Expected Output*: All 5 files accepted into a single batch with sequence 1 through 5.
  - *Verification*: Batch created with `expectedCount == 5`.
- **TC-T1-R402-05: Drop-Zone Dismissal and Auto-Hide**
  - *Input*: Drag operation completes or user presses Escape.
  - *Expected Output*: Floating drop zone fades out smoothly.
  - *Verification*: Window `isVisible == false`.

### FEAT-R5-01: macOS Sequoia Liquid Glass & 3-Column HIG
*Source: M5 / R5.1, Survey*
- **TC-T1-R501-01: NavigationSplitView 3-Column Hierarchy**
  - *Input*: App main window layout initialization.
  - *Expected Output*: 3-column split view: Sidebar (Navigation), Content List (Batches/Jobs), Detail (Transcript/Player).
  - *Verification*: Split view hierarchy conforms to macOS HIG.
- **TC-T1-R501-02: NSVisualEffectView Vibrancy & Material**
  - *Input*: Inspect sidebar and background materials.
  - *Expected Output*: Uses `.sidebar` material with `.behindWindow` blending mode for Liquid Glass translucency.
  - *Verification*: Visual effect view configuration verified.
- **TC-T1-R501-03: Unified Window Toolbar with Search & Controls**
  - *Input*: Main window toolbar render.
  - *Expected Output*: Toolbar includes search field, playback controls, record button, and export action.
  - *Verification*: Toolbar items are present and responsive.
- **TC-T1-R501-04: SF Symbols 6 Integration**
  - *Input*: UI icons across toolbar, sidebar, and buttons.
  - *Expected Output*: Uses native SF Symbols (e.g. `waveform`, `mic.fill`, `play.fill`, `person.2.fill`).
  - *Verification*: Images load successfully from system symbol catalog.
- **TC-T1-R501-05: Dynamic Dark / Light Mode Adaptation**
  - *Input*: Toggle system appearance between Dark and Light mode.
  - *Expected Output*: Vibrancy, text colors, and waveform visuals adapt automatically without restart.
  - *Verification*: Interface updates cleanly on appearance change notification.

### FEAT-R5-02: Shortcuts & Quick Look Previews
*Source: M5 / R5.2, R5.3, AC#3, Survey*
- **TC-T1-R502-01: Spacebar Play/Pause Shortcut**
  - *Input*: Press Spacebar while transcript view has focus.
  - *Expected Output*: Toggles playback state between playing and paused.
  - *Verification*: Player toggles state.
- **TC-T1-R502-02: ⌘K Command Palette Invocation**
  - *Input*: Press ⌘K.
  - *Expected Output*: Quick command palette modal appears offering search, model switch, and export actions.
  - *Verification*: Command palette state transitions to visible.
- **TC-T1-R502-03: ⌘F Interactive In-Transcript Search**
  - *Input*: Press ⌘F, type search term, press Enter / ⌘G.
  - *Expected Output*: Matching transcript terms highlighted; playhead can navigate between search hits.
  - *Verification*: Hit count matches occurrences; hit navigation scrolls to match.
- **TC-T1-R502-04: ⌘E Instant Multi-Format Export**
  - *Input*: Press ⌘E on completed transcript.
  - *Expected Output*: Export dialog or instant quick-export action triggered for selected format (SRT, VTT, TXT, JSON).
  - *Verification*: Export workflow begins.
- **TC-T1-R502-05: Quick Look Preview Item Generation**
  - *Input*: Select transcript item and press Spacebar in Finder or file list.
  - *Expected Output*: Quick Look preview generated displaying formatted transcript with header metadata.
  - *Verification*: `QLPreviewItem` returns valid preview URL.

### FEAT-R6-01: Extreme Performance & Lean Binary
*Source: M6 / R6.1, R6.3, AC#8, AC#9, Survey*
- **TC-T1-R601-01: App Cold Launch Time (<200ms)**
  - *Input*: App launch benchmark on Apple Silicon.
  - *Expected Output*: Cold launch to first UI frame completes in $< 200$ ms.
  - *Verification*: Clock measurement from entry point to view display is $< 0.200$s.
- **TC-T1-R601-02: Lean Binary / DMG Size Footprint (<10MB)**
  - *Input*: Packaged release DMG or compiled app bundle.
  - *Expected Output*: Total binary size strictly $< 15$ MB (target $< 10$ MB).
  - *Verification*: Check file size via `stat -f%z`.
- **TC-T1-R601-03: Zero Third-Party Dependency Mandate**
  - *Input*: Package manifest dependencies inspection.
  - *Expected Output*: Only `GRDB.swift` and `whisper.xcframework` linked; zero bloated web/electron/utility dependencies.
  - *Verification*: `Package.swift` contains no unapproved dependencies.
- **TC-T1-R601-04: Accelerate/vDSP Memory Zero-Copy**
  - *Input*: Audio downsampling and signal processing.
  - *Expected Output*: Samples processed in-place via pointer buffers without redundant array allocations.
  - *Verification*: Peak memory allocation during 10-minute audio processing remains $< 50$ MB.
- **TC-T1-R601-05: Swift 6 Strict Concurrency Clean Compilation**
  - *Input*: Build target with `-enable-experimental-feature StrictConcurrency`.
  - *Expected Output*: Compiles cleanly with zero concurrency warnings or data race diagnostics.
  - *Verification*: Build output contains zero concurrency diagnostic warnings.

### FEAT-R6-02: Zero-Regression Suite Pass
*Source: M6 / R6.2, AC#10, AC#11, Survey*
- **TC-T1-R602-01: Baseline 39 Unit Tests 100% Pass**
  - *Input*: Run full existing test suite (`swift test`).
  - *Expected Output*: All 39 existing unit and integration tests pass without a single failure.
  - *Verification*: Swift testing output confirms 0 failures across all suites.
- **TC-T1-R602-02: OutputWriter Collision & Sanitization Regression**
  - *Input*: Sequential collisions and special characters in filenames.
  - *Expected Output*: Sanitization and numbering `(2)`, `(3)` function exactly as originally tested.
  - *Verification*: `OutputWriterTests` pass cleanly.
- **TC-T1-R602-03: URLParser Bulk & Playlist Ingestion Regression**
  - *Input*: Dirty strings containing YouTube URLs and invalid links.
  - *Expected Output*: Deduplication and URL extraction function without regression.
  - *Verification*: `ComprehensiveURLParserTests` pass cleanly.
- **TC-T1-R602-04: PostProcessor Hallucination Break Regression**
  - *Input*: Repetition loops ("Evet" x10) and noise tags.
  - *Expected Output*: Loops broken at threshold $\le 2$; noise tags stripped cleanly.
  - *Verification*: `PostProcessorDeepTests` pass cleanly.
- **TC-T1-R602-05: Batch Database Migration & Recovery Regression**
  - *Input*: Database migration v1 and v2, crash recovery check.
  - *Expected Output*: Migrations execute cleanly; crash recovery restores interrupted batches.
  - *Verification*: `BatchDatabaseTests` and `BatchAndJobLifecycleTests` pass cleanly.

---

## 3. Tier 2: Boundary & Corner Cases (5 Test Cases per Feature across 22 Features)

### Boundary Cases: FEAT-R1-01 (Token Timestamps)
- **TC-T2-R101-01: Zero-Duration Token Handling**
  - *Input*: Audio segment where word has start == end timestamp (0ms duration).
  - *Expected Output*: Token timestamp normalized to minimum non-zero duration ($\ge 10$ms) or handled without zero-division.
- **TC-T2-R101-02: Massive Word Token Count (100,000+ words)**
  - *Input*: Multi-hour continuous recording generating $>100,000$ word tokens.
  - *Expected Output*: Memory usage remains bounded; search and index lookups complete in $< 1$ms.
- **TC-T2-R101-03: Overlapping Token Timestamps**
  - *Input*: Token A (0.500 - 1.200s), Token B (1.000 - 1.500s).
  - *Expected Output*: Karaoke active word selector resolves overlap deterministically to the latest or highest-confidence token.
- **TC-T2-R101-04: Non-Ascii / Extended Emoji Tokens**
  - *Input*: Words with Turkish characters (ş, ğ, ç, ı, ö, ü) and emojis.
  - *Expected Output*: UTF-8 byte boundary preservation; no text clipping or encoding corruption.
- **TC-T2-R101-05: Infinite / NaN Float Timestamps**
  - *Input*: Corrupt token data containing `Float.infinity` or `Float.nan`.
  - *Expected Output*: Engine clamps or drops corrupt tokens, preventing UI layout crash.

### Boundary Cases: FEAT-R1-02 (Native Audio Player Controller)
- **TC-T2-R102-01: Seek to Negative Timestamp**
  - *Input*: `seek(to: -10.0)`.
  - *Expected Output*: Clamped to $0.0$ seconds; playback continues smoothly.
- **TC-T2-R102-02: Seek Beyond File Duration**
  - *Input*: Duration = 60s; `seek(to: 120.0)`.
  - *Expected Output*: Clamped to `duration` (60.0s); player enters completed/paused state.
- **TC-T2-R102-03: Rapid Fire Scrubbing (100 seeks in 100ms)**
  - *Input*: 100 rapid seek calls dispatched concurrently.
  - *Expected Output*: No audio buffer underruns, race conditions, or audio engine crashes; playhead lands at final seek target.
- **TC-T2-R102-04: Zero-Length Audio File Loading**
  - *Input*: Attempt to load 0-byte or 0-duration audio file.
  - *Expected Output*: Throws typed error `unsupportedMedia`; player state remains safely idle.
- **TC-T2-R102-05: Missing File Path on Disk**
  - *Input*: `load(url: URL(fileURLWithPath: "/non/existent/audio.m4a"))`.
  - *Expected Output*: Throws `fileNotFound` without crashing player controller.

### Boundary Cases: FEAT-R1-03 (vDSP Waveform Generator)
- **TC-T2-R103-01: Pure Digital Silence Buffer (All Zeros)**
  - *Input*: 100,000 float samples of value `0.0`.
  - *Expected Output*: Waveform points with `min: 0.0, max: 0.0` without NaN or division by zero.
- **TC-T2-R103-02: Extreme DC Offset Signal**
  - *Input*: Signal with constant DC bias of $+0.9$ plus tiny AC ripple.
  - *Expected Output*: Normalization algorithm removes or handles DC offset; envelope points stay strictly in $[0.0, 1.0]$.
- **TC-T2-R103-03: Severely Clipped Signal (Values $> 1.0$)**
  - *Input*: Audio samples with values exceeding $+3.0$ and $-3.0$ (digital distortion).
  - *Expected Output*: Peak envelope clamped cleanly to $1.0$ without numeric overflow.
- **TC-T2-R103-04: Minimal Sample Count (1 to 5 samples)**
  - *Input*: Target points = 100, but audio buffer only contains 3 samples.
  - *Expected Output*: Interpolates or pads gracefully; returns valid array of 100 points without memory segmentation fault.
- **TC-T2-R103-05: Huge Target Points Request (100,000 points)**
  - *Input*: Target points = 100,000.
  - *Expected Output*: Generates high-resolution envelope without memory exhaustion or crash.

### Boundary Cases: FEAT-R1-04 (Interactive Waveform Visualizer)
- **TC-T2-R104-01: Zero Width View Bounds**
  - *Input*: View frame geometry has `width == 0` or `height == 0`.
  - *Expected Output*: Drawing loop skips render cycle cleanly without division by zero.
- **TC-T2-R104-02: Click Out-of-Bounds (Negative or Beyond Width)**
  - *Input*: Click event at $x = -50$px or $x = 1500$px (where width = 1000px).
  - *Expected Output*: Seek target clamped to $0.0$ and duration respectively.
- **TC-T2-R104-03: Extreme Zoom Level Scrubbing**
  - *Input*: Waveform zoomed in to 1 second per 1000px.
  - *Expected Output*: Scrubbing maintains sub-millisecond precision without jitter.
- **TC-T2-R104-04: Rapid Window Resizing**
  - *Input*: Window resized continuously between 400px and 2560px width.
  - *Expected Output*: Waveform re-renders dynamically at target resolution without frame lockups.
- **TC-T2-R104-05: Empty Waveform Points Array**
  - *Input*: `WaveformPoint` array is empty `[]`.
  - *Expected Output*: View renders placeholder shimmer or flat baseline without crashing.

### Boundary Cases: FEAT-R1-05 (Karaoke Synchronized Transcript)
- **TC-T2-R105-01: Playhead Past End of Transcript**
  - *Input*: Playhead at $t = 100.0$s; last word ends at $t = 80.0$s.
  - *Expected Output*: Active word index is safely nil or clamped to last word; no index out of bounds.
- **TC-T2-R105-02: Playhead Before First Word**
  - *Input*: Playhead at $t = 0.5$s; first word starts at $t = 5.0$s.
  - *Expected Output*: Active word index is safely nil; no word highlighted.
- **TC-T2-R105-03: Zero Words in Segment**
  - *Input*: Segment containing empty text `""` and empty word array `[]`.
  - *Expected Output*: Handled gracefully without crash; karaoke view renders empty segment cleanly.
- **TC-T2-R105-04: Click on Word in Empty Segment**
  - *Input*: User interaction on malformed segment.
  - *Expected Output*: No seek dispatch; error logged.
- **TC-T2-R105-05: Highly Concurrent Click & Playback Updates**
  - *Input*: 50 rapid word clicks while audio is continuously streaming time updates.
  - *Expected Output*: No race conditions; UI highlights clicked word and synchronizes audio.

### Boundary Cases: FEAT-R1-06 (Audio Session Media Retention)
- **TC-T2-R106-01: Disk Full During Ingestion**
  - *Input*: Free disk space $< 5$ MB during audio download or copy.
  - *Expected Output*: Throws `insufficientDiskSpace`; cleans up partial files; notifies user.
- **TC-T2-R106-02: Read-Only Storage Directory**
  - *Input*: Storage path permissions set to `0444` (read-only).
  - *Expected Output*: Catches permission error and requests or uses fallback writable temporary directory.
- **TC-T2-R106-03: Sudden App Termination (SIGKILL Simulation)**
  - *Input*: Process killed during session media write.
  - *Expected Output*: Atomic file write ensures partial files are not left in corrupt state on subsequent launch.
- **TC-T2-R106-04: Path with Unicode and Spaces**
  - *Input*: Audio saved to `/Users/akif/Örnek Sesler/Kayıt #1 [test].m4a`.
  - *Expected Output*: Path encoding handled correctly; file loads and plays without path formatting errors.
- **TC-T2-R106-05: Concurrent Deletion of Underneath File**
  - *Input*: External process deletes retained audio file while player is active.
  - *Expected Output*: Controller detects missing resource gracefully and halts playback without crash.

### Boundary Cases: FEAT-R2-01 (Audio & Mic Recording Engine)
- **TC-T2-R201-01: Disconnect Microphone During Active Recording**
  - *Input*: Audio hardware device route changes or unplugs while `isRecording == true`.
  - *Expected Output*: Audio engine catches route change notification, pauses/stops recording cleanly, and saves captured audio.
- **TC-T2-R201-02: Zero Frames Captured**
  - *Input*: Audio engine started and stopped within 1 millisecond.
  - *Expected Output*: Detects 0 frames; discards empty file; does not throw unhandled exception.
- **TC-T2-R201-03: Long Duration Recording (10+ Hours)**
  - *Input*: Continuous recording over multiple hours.
  - *Expected Output*: Audio segmented or buffered without 32-bit frame counter overflow; memory consumption stays constant.
- **TC-T2-R201-04: Audio Buffer Allocation Failure**
  - *Input*: Memory pressure causing buffer allocation to return nil.
  - *Expected Output*: Throws `conversionFailed` or `outOfMemory` error gracefully.
- **TC-T2-R201-05: Multiple Start Calls in Rapid Succession**
  - *Input*: Consecutive calls to `startRecording()` without stopping.
  - *Expected Output*: Subsequent calls are rejected or ignored (`alreadyRecording` state guard).

### Boundary Cases: FEAT-R2-02 (Real-Time Audio Level Metering)
- **TC-T2-R202-01: Float Invalids in Audio Buffer (NaN/Inf)**
  - *Input*: Corrupted buffer with `Float.nan` samples.
  - *Expected Output*: Metering algorithm filters non-finite values; output remains valid float in $[0.0, 1.0]$.
- **TC-T2-R202-02: Single-Sample Impulse (Delta Function)**
  - *Input*: Buffer with 999 zeros and a single `1.0` spike.
  - *Expected Output*: Level meter registers instant peak without numerical instability.
- **TC-T2-R202-03: Extreme High Frequency (> 20kHz)**
  - *Input*: Inaudible ultrasonic tone at 22kHz.
  - *Expected Output*: Filtered according to Nyquist limit without aliasing artifacts crashing FFT analyzer.
- **TC-T2-R202-04: Zero Band Magnitude Sum**
  - *Input*: Complete silence across all frequency bins.
  - *Expected Output*: Frequency band outputs are all zero arrays without division by zero.
- **TC-T2-R202-05: Massive FFT Window Buffer**
  - *Input*: Metering window size = 65,536 samples.
  - *Expected Output*: FFT calculation executes within real-time deadline or falls back safely.

### Boundary Cases: FEAT-R2-03 (Live Frequency Bar Visualizer)
- **TC-T2-R203-01: Negative Band Magnitudes**
  - *Input*: Erroneous negative values passed to visualizer.
  - *Expected Output*: Clamped to 0.0; bar renders at baseline.
- **TC-T2-R203-02: Extreme High Number of Frequency Bars (128 bars)**
  - *Input*: Array of 128 frequency bands.
  - *Expected Output*: View automatically packs or downsamples bars to fit screen width without overlapping.
- **TC-T2-R203-03: Display Refresh Rate Throttling (ProMotion 120Hz to Low Power 30Hz)**
  - *Input*: System transitions into Low Power Mode.
  - *Expected Output*: Visualizer throttles animation frame rate gracefully without animation stutter.
- **TC-T2-R203-04: Sudden Nil Data Input**
  - *Input*: State updates with empty band array during view refresh.
  - *Expected Output*: Renders baseline bars without crash.
- **TC-T2-R203-05: Window Hidden / Minimized Animation Suspend**
  - *Input*: Window minimized to Dock.
  - *Expected Output*: Visualizer animation stops, dropping GPU/CPU utilization to zero.

### Boundary Cases: FEAT-R2-04 (Instant Auto-Transcribe & Auto-Save)
- **TC-T2-R204-01: Auto-Transcribe on Extremely Short Recording (< 0.5s)**
  - *Input*: User records for 0.2s and stops.
  - *Expected Output*: Engine processes file; handles empty transcript or short utterance without crashing Whisper engine.
- **TC-T2-R204-02: Auto-Transcribe While Whisper Engine is Busy**
  - *Input*: A batch job is actively running when recording stops.
  - *Expected Output*: Recorded job is queued prioritized in queue; does not collide with active engine instance.
- **TC-T2-R204-03: Auto-Save Path Removed While Transcribing**
  - *Input*: Configured export folder deleted while auto-transcribe is executing.
  - *Expected Output*: Recreates directory or falls back to application default directory with warning log.
- **TC-T2-R204-04: Title Name Collision on Auto-Save**
  - *Input*: File with default name "Kayıt 2026-10-15" already exists.
  - *Expected Output*: `OutputWriter` resolves collision with sequential suffix "Kayıt 2026-10-15 (2)".
- **TC-T2-R204-05: Transcription Failure During Auto-Save**
  - *Input*: Model file missing or corrupted during auto-transcribe.
  - *Expected Output*: Job state marked `.failed`; original recorded audio file preserved in user storage for retry.

### Boundary Cases: FEAT-R2-05 (Recording Entitlements & Privacy)
- **TC-T2-R205-01: System Revocation of Mic Permission During Recording**
  - *Input*: User toggles off microphone permission in System Settings while recording is active.
  - *Expected Output*: OS halts audio stream; engine handles failure notification cleanly, saving existing buffer.
- **TC-T2-R205-02: Restricted Permission (Parental Controls / MDM)**
  - *Input*: Device is restricted under MDM profile with mic access disabled.
  - *Expected Output*: Reports `.restricted` status; UI displays descriptive enterprise policy message.
- **TC-T2-R205-03: Rapid Permission Toggle Query**
  - *Input*: 100 concurrent checks of authorization status.
  - *Expected Output*: Non-blocking, thread-safe resolution without deadlocks.
- **TC-T2-R205-04: Headless CLI Execution Without Window Server**
  - *Input*: Running `transkripthub-cli` in headless SSH session.
  - *Expected Output*: CLI detects headless environment and avoids presenting GUI permission prompts.
- **TC-T2-R205-05: Missing Entitlements in Debug Build**
  - *Input*: Binary compiled without microphone entitlement.
  - *Expected Output*: Fails with explicit error diagnostic rather than silent crash.

### Boundary Cases: FEAT-R3-01 (Acoustic Turn Diarization)
- **TC-T2-R301-01: Rapid-Fire Staccato Dialogue (< 200ms turns)**
  - *Input*: Fast dialogue where speakers exchange 1-word responses every 300ms.
  - *Expected Output*: Diarizer maintains distinct turns without merging distinct speakers into one.
- **TC-T2-R301-02: Prolonged Silence (60+ seconds between utterances)**
  - *Input*: 60s silence between two statements by same speaker.
  - *Expected Output*: Evaluates acoustic profile to avoid creating artificial new speakers purely on silence length.
- **TC-T2-R301-03: 10+ Speakers in a Single Meeting**
  - *Input*: Large roundtable conference with 12 distinct voices.
  - *Expected Output*: Successfully assigns up to 12 distinct speaker labels without index overflow.
- **TC-T2-R301-04: Background Noise with Intermittent Speech**
  - *Input*: High background cafe noise (low SNR).
  - *Expected Output*: Noise segments filtered out; diarization targets only speech segments.
- **TC-T2-R301-05: Zero Voice Segments (Ambient Recording)**
  - *Input*: Recording containing only ambient rain sound.
  - *Expected Output*: Returns empty or single ambient segment without failure.

### Boundary Cases: FEAT-R3-02 (Colored Speaker Badges & Rename)
- **TC-T2-R302-01: Speaker Name with Extreme Length (500+ characters)**
  - *Input*: Rename speaker to 500-character string.
  - *Expected Output*: UI truncates with ellipsis; database stores complete string without buffer overflow.
- **TC-T2-R302-02: Renaming to an Existing Speaker Name (Merge Collision)**
  - *Input*: "Speaker 2" renamed to "Speaker 1".
  - *Expected Output*: Prompts user or merges speaker turns under unified label with consistent color badge.
- **TC-T2-R302-03: Renaming with Empty String or Whitespace Only**
  - *Input*: Rename input is `""` or `"   "`.
  - *Expected Output*: Rejects empty name; reverts to default "Speaker N" label.
- **TC-T2-R302-04: Renaming with HTML / Script Tags**
  - *Input*: Rename to `<script>alert('xss')</script>`.
  - *Expected Output*: Sanitized as plain text string; prevents injection in export formats (HTML/Markdown).
- **TC-T2-R302-05: High Palette Index Wrap-Around (Speaker 25+)**
  - *Input*: Transcript with 25 speakers; palette contains 8 primary colors.
  - *Expected Output*: Palette loops deterministically using modulo arithmetic without crashing.

### Boundary Cases: FEAT-R3-03 (Inline Rich Transcript Editor)
- **TC-T2-R303-01: Editing Entire Transcript to Empty String**
  - *Input*: User selects all text and deletes it.
  - *Expected Output*: Handles empty text gracefully; segment models clear text; database updates.
- **TC-T2-R303-02: Massive Paste (1,000,000 characters)**
  - *Input*: Pasting 1 million characters into an inline segment.
  - *Expected Output*: Editor processes paste without beachballing UI; memory footprint remains stable.
- **TC-T2-R303-03: Rapid Concurrent Edits in Multiple Segments**
  - *Input*: Fast keyboard input across adjacent segments.
  - *Expected Output*: Focus transitions smoothly; debounced auto-save captures all modifications.
- **TC-T2-R303-04: Non-Latin and Right-to-Left (RTL) Scripts**
  - *Input*: Editing Arabic or Hebrew text inline.
  - *Expected Output*: Text alignment and cursor movement adapt correctly according to text direction.
- **TC-T2-R303-05: Special Control Characters in Text**
  - *Input*: Text containing null bytes `\0`, carriage returns `\r`, or tabs `\t`.
  - *Expected Output*: Sanitized or preserved without corrupting underlying database strings.

### Boundary Cases: FEAT-R3-04 (Atomic Database Model Sync)
- **TC-T2-R304-01: Update Non-Existent Job ID**
  - *Input*: `updateTranscript(jobId: "invalid-uuid", newText: "...", segments: [])`.
  - *Expected Output*: Throws `recordNotFound` or handles non-existent foreign key safely.
- **TC-T2-R304-02: Malformed JSON String in Segments Column**
  - *Input*: Direct injection of malformed JSON string into `segments` column.
  - *Expected Output*: Model parser catches decode error gracefully and falls back to plain text reconstruction.
- **TC-T2-R304-03: Concurrent Multi-Threaded Updates on Same Job**
  - *Input*: 20 concurrent async tasks updating the same transcript record.
  - *Expected Output*: Serialized through GRDB transaction queue; zero database locking deadlock (`SQLITE_BUSY`).
- **TC-T2-R304-04: Database File Locked by External Backup Utility**
  - *Input*: SQLite database file locked temporarily by Time Machine or backup process.
  - *Expected Output*: GRDB busy handler retries up to timeout (e.g. 5 seconds) before surfacing error.
- **TC-T2-R304-05: Extremely Large Segment Payload (50MB JSON)**
  - *Input*: Updating transcript with 50,000 segments.
  - *Expected Output*: SQLite handles large text blob atomically within transaction memory limits.

### Boundary Cases: FEAT-R3-05 (Local Summary & Chaptering)
- **TC-T2-R305-01: Summarize Extremely Short Transcript (1 sentence)**
  - *Input*: Transcript: "Toplantı saat 10'da başladı ve bitti."
  - *Expected Output*: Returns the sentence as summary without failing minimum sentence thresholds.
- **TC-T2-R305-02: Summarize Non-Grammatical Transcript (Gibberish)**
  - *Input*: Transcript consisting of random tokens or repeated single characters.
  - *Expected Output*: NaturalLanguage parser handles without crashing; returns best-effort or empty summary.
- **TC-T2-R305-03: Chaptering with Flat Topic Distribution (No clear boundaries)**
  - *Input*: Continuous monologue about a single subject without paragraph breaks.
  - *Expected Output*: Generates evenly spaced time-based chapters (e.g. every 5 minutes).
- **TC-T2-R305-04: Multilingual Mixed Transcript Summarization**
  - *Input*: Mixed Turkish and English conversation.
  - *Expected Output*: NaturalLanguage detects multilingual boundaries; generates coherent bilingual summary.
- **TC-T2-R305-05: Memory Pressure During NLP Tokenization**
  - *Input*: Massive text processed on low-memory condition.
  - *Expected Output*: Sentence tokenization iterates in streaming chunks rather than single memory allocation.

### Boundary Cases: FEAT-R4-01 (Menu Bar Drag-and-Drop Extra)
- **TC-T2-R401-01: Dropping Non-Audio / Executable Files**
  - *Input*: User drags a `.zip`, `.exe`, or `.dmg` file onto Menu Bar icon.
  - *Expected Output*: Drop rejected with visual error shake; no invalid job created.
- **TC-T2-R401-02: Dropping 100 Files Simultaneously**
  - *Input*: Drag-and-drop of 100 audio files at once.
  - *Expected Output*: All 100 files validated and queued in batch without UI freeze.
- **TC-T2-R401-03: Dropping Malformed URL String**
  - *Input*: Dropping text: "htp:/not-a-valid-url".
  - *Expected Output*: Rejection notification; error logged.
- **TC-T2-R401-04: Rapid Clicking on Menu Bar Item**
  - *Input*: User clicks menu bar icon 20 times in 2 seconds.
  - *Expected Output*: Popover toggles cleanly without window leak or multiple overlapping popovers.
- **TC-T2-R401-05: Menu Bar Item When Full Screen App is Active**
  - *Input*: Main app or third-party app in macOS Spaces Full Screen mode.
  - *Expected Output*: Status item remains accessible or opens companion in active space.

### Boundary Cases: FEAT-R4-02 (Floating Drop-Zone & Quick Dictation)
- **TC-T2-R402-01: Dragging Floating Panel Beyond Screen Edges**
  - *Input*: User drags floating widget off the visible screen frame.
  - *Expected Output*: Clamped to visible screen bounds so it never becomes lost off-screen.
- **TC-T2-R402-02: Multiple Display Setup (Display Disconnect)**
  - *Input*: Floating zone on external monitor, which is then unplugged.
  - *Expected Output*: Repositions automatically onto main display.
- **TC-T2-R402-03: Hotkey Press When Another App Has Exclusive Grab**
  - *Input*: Game or virtualization software capturing keyboard exclusively.
  - *Expected Output*: Handles failure to register hotkey without crash.
- **TC-T2-R402-04: Quick Dictation in Empty Clipboard State**
  - *Input*: Clipboard empty before dictation.
  - *Expected Output*: Successfully sets clipboard to new text without pasteboard failure.
- **TC-T2-R402-05: Floating Widget Resizing to Zero**
  - *Input*: Attempt to collapse or shrink widget below minimum dimensions.
  - *Expected Output*: Minimum size constraints enforce compact but functional drop zone (e.g. 120x120px).

### Boundary Cases: FEAT-R5-01 (macOS Sequoia Liquid Glass & 3-Column HIG)
- **TC-T2-R501-01: Window Collapsed to Minimum Allowable Size**
  - *Input*: Resize window to 600x400 minimum size.
  - *Expected Output*: 3-column split view collapses sidebar cleanly into overlay without clipping controls.
- **TC-T2-R501-02: macOS High Contrast Accessibility Mode**
  - *Input*: System setting "Increase Contrast" enabled in Accessibility.
  - *Expected Output*: Liquid glass vibrancy borders become crisp solid borders for high contrast compliance.
- **TC-T2-R501-03: Window Opened on Legacy macOS (macOS 14 Sonoma Compatibility)**
  - *Input*: Running on macOS 14 vs macOS 15/Sequoia.
  - *Expected Output*: Backward compatible visual effects render cleanly without missing symbol crashes.
- **TC-T2-R501-04: Rapid Multi-Window Spawning**
  - *Input*: User opens multiple document windows (⌘N).
  - *Expected Output*: Each window manages its own view state and player instance independently.
- **TC-T2-R501-05: Right-to-Left System Localization**
  - *Input*: macOS system language set to Arabic.
  - *Expected Output*: 3-column navigation mirrors cleanly (Sidebar on right, detail on left).

### Boundary Cases: FEAT-R5-02 (Shortcuts & Quick Look Previews)
- **TC-T2-R502-01: Spacebar Pressed While Text Field Has Focus**
  - *Input*: Spacebar pressed while cursor is inside inline transcript editor text field.
  - *Expected Output*: Inserts space character into text; DOES NOT trigger play/pause.
- **TC-T2-R502-02: ⌘F Search with Zero Matches**
  - *Input*: Search query: "xyz123nonexistent".
  - *Expected Output*: Search indicates 0 hits; navigation buttons disable gracefully; no crash.
- **TC-T2-R502-03: ⌘F Search with 10,000 Matches**
  - *Input*: Search for single common letter "e" in massive document.
  - *Expected Output*: Matches indexed asynchronously; UI highlights visible matches without beachball.
- **TC-T2-R502-04: ⌘K Invocation While Modal Sheet is Already Open**
  - *Input*: Settings sheet open; user presses ⌘K.
  - *Expected Output*: Command palette opens above modal sheet or manages focus cleanly.
- **TC-T2-R502-05: Quick Look Preview on Incomplete / Failed Job**
  - *Input*: Quick Look triggered on job in `.failed` state.
  - *Expected Output*: Quick Look renders error summary card rather than blank preview.

### Boundary Cases: FEAT-R6-01 (Extreme Performance & Lean Binary)
- **TC-T2-R601-01: Launch Under Severe CPU Contention**
  - *Input*: Launch app while 100% CPU is utilized by external compilation.
  - *Expected Output*: Launches cleanly without watchdog timeout or watchdog crash.
- **TC-T2-R601-02: Binary Code Signature Integrity**
  - *Input*: Inspect code signature (`codesign --verify --deep`).
  - *Expected Output*: Zero signature errors, strict entitlement adherence.
- **TC-T2-R601-03: Memory Leak Detection Across 1,000 Audio Playback Cycles**
  - *Input*: Load, play, seek, and unload audio file 1,000 times in loop.
  - *Expected Output*: Steady-state heap memory growth is zero bytes; no retain cycles in player or observers.
- **TC-T2-R601-04: Non-Accelerate Fallback Verification**
  - *Input*: Audio signal processing on non-vectorized path.
  - *Expected Output*: Produces mathematically equivalent envelope to vDSP path.
- **TC-T2-R601-05: Maximum Active Threads Limit Enforcement**
  - *Input*: Process multi-channel audio with `TranscriptionOptions(threads: 32)`.
  - *Expected Output*: Thread count clamped to `min(activeProcessorCount, 6)` preventing thread explosion.

### Boundary Cases: FEAT-R6-02 (Zero-Regression Suite Pass)
- **TC-T2-R602-01: Legacy v1 Database Migration with Dirty Rows**
  - *Input*: Migrate v1 database containing null `external_id` or null `segments`.
  - *Expected Output*: Migration succeeds without constraint failure; fills sensible defaults.
- **TC-T2-R602-02: Filename Sanitization with 200+ Unicode Characters**
  - *Input*: Video title with 300 emojis, slashes, and control characters.
  - *Expected Output*: Truncated safely to $\le 150$ chars at valid Unicode grapheme cluster boundary.
- **TC-T2-R602-03: AudioValidator on Zero-Byte File**
  - *Input*: Empty 0-byte file with `.mp3` extension.
  - *Expected Output*: Throws `emptyFile` error.
- **TC-T2-R602-04: PostProcessor Silence Threshold Chunking on Single Block**
  - *Input*: Transcript segments with no silence gaps greater than threshold.
  - *Expected Output*: Groups into single paragraph without error.
- **TC-T2-R602-05: FolderWatcher Rapid Create-Delete-Create Cycle**
  - *Input*: File created and deleted within 5ms inside watched directory.
  - *Expected Output*: Watcher event debounced; avoids attempting to process deleted file.

---

## 4. Tier 3: Cross-Feature Combinations (Pairwise & Multi-Feature Interactions)

### Matrix of Key Cross-Feature Interactions

| Interaction ID | Features Involved | Verification Scenario |
|---|---|---|
| **XFEAT-01** | FEAT-R2-01 + FEAT-R2-02 + FEAT-R2-03 | Direct Recording with Live RMS Metering & Animated Frequency Bars |
| **XFEAT-02** | FEAT-R2-01 + FEAT-R2-04 + FEAT-R3-04 | Audio Recording Stop -> Auto-Transcribe -> Atomic Database Insertion |
| **XFEAT-03** | FEAT-R1-02 + FEAT-R1-03 + FEAT-R1-04 | Loaded Audio -> vDSP Waveform Generation -> Interactive Scrub & Seek |
| **XFEAT-04** | FEAT-R1-02 + FEAT-R1-05 + FEAT-R5-02 | Spacebar Toggle -> Playback Progress -> Karaoke Word Illumination |
| **XFEAT-05** | FEAT-R1-05 + FEAT-R1-02 + FEAT-R1-04 | Transcript Word Click -> ±100ms Playhead Seek -> Waveform Scrub Bar Sync |
| **XFEAT-06** | FEAT-R3-01 + FEAT-R3-02 + FEAT-R3-03 | Acoustic Diarization -> Colored Badges -> Inline Speaker Renaming |
| **XFEAT-07** | FEAT-R3-03 + FEAT-R3-04 + FEAT-R1-05 | Inline Transcript Text Correction -> Atomic DB Save -> Karaoke Retains Timestamps |
| **XFEAT-08** | FEAT-R4-01 + FEAT-R1-06 + FEAT-R1-02 | Menu Bar File Drop -> Media Retention in Session -> Immediate Playback Readiness |
| **XFEAT-09** | FEAT-R4-02 + FEAT-R2-01 + FEAT-R2-04 | Global Dictation Hotkey -> In-App Recording -> Instant Clipboard & History |
| **XFEAT-10** | FEAT-R3-05 + FEAT-R5-02 + FEAT-R3-04 | Local NaturalLanguage Chaptering -> ⌘K Navigation Jump -> Database Persistence |

### Detailed Cross-Feature Test Specifications

- **TC-T3-XFEAT-01: Recording Engine & Metering Real-Time Pipeline**
  - *Flow*: `AudioRecordingEngine.startRecording()` initializes input node tap. PCM buffers flow into `RealTimeLevelMeter` and `vDSP FrequencyAnalyzer`.
  - *Verification*: Meter level and frequency bands update synchronously with input volume changes without dropping audio frames.
- **TC-T3-XFEAT-02: Recording Stop to Atomic Persistence Pipeline**
  - *Flow*: `stopRecording()` returns audio file URL. File is passed to transcription engine. Resulting text and segments are saved via `updateTranscript` on `AppDatabase`.
  - *Verification*: Querying database confirms job record transitions to `.completed` with valid `transcript_section` content.
- **TC-T3-XFEAT-03: Audio Load, Waveform Downsample, and Seek Synchrony**
  - *Flow*: `AudioPlayerController.load(url)` loads audio. Concurrently, `WaveformGenerator` generates 200 points in $<15$ms. User clicks at point index 50 ($25\%$ progress).
  - *Verification*: Player seeks to $0.25 \times \text{duration} \pm 100$ms; visualizer indicator moves to match.
- **TC-T3-XFEAT-04: Playback, Spacebar Shortcut, and Karaoke Word Highlighting**
  - *Flow*: Press Spacebar -> `AudioPlayerController.play()`. As `currentTime` increments, karaoke view updates active word. Press Spacebar -> `pause()`.
  - *Verification*: Active word illumination matches current audio playhead time continuously.
- **TC-T3-XFEAT-05: Karaoke Click-to-Seek Feedback Loop**
  - *Flow*: User clicks on word 42 (start: 14.22s). `AudioPlayerController.seek(to: 14.22)` is executed. Waveform playhead updates to 14.22s.
  - *Verification*: `abs(controller.currentTime - 14.22) <= 0.100`; waveform scrub position reflects $14.22 / \text{duration}$.
- **TC-T3-XFEAT-06: Diarization to Badge Renaming Pipeline**
  - *Flow*: Acoustic diarizer groups segments into "Speaker 1" and "Speaker 2". User renames "Speaker 1" to "Ayşe".
  - *Verification*: All segments for "Speaker 1" update to "Ayşe" and retain their distinct color badge index.
- **TC-T3-XFEAT-07: Inline Text Editing with Atomic DB Sync & Word Preservation**
  - *Flow*: User edits text of segment 3. Updated text is committed to `AppDatabase` atomically. User plays audio.
  - *Verification*: Word-level timestamps continue to drive karaoke highlighting accurately while displaying edited text.
- **TC-T3-XFEAT-08: Menu Bar Drop to Audio Playback Pipeline**
  - *Flow*: Audio file dropped onto menu bar companion -> saved to session storage -> loaded into `AudioPlayerController`.
  - *Verification*: Media is retained and playable immediately without UI hitch.
- **TC-T3-XFEAT-09: Global Hotkey Quick Dictation Flow**
  - *Flow*: Hotkey pressed -> recording starts -> hotkey released -> transcribed -> copied to pasteboard -> saved to history.
  - *Verification*: Pasteboard contains transcribed text; database history table contains new entry.
- **TC-T3-XFEAT-10: Chaptering Navigation & Database Persistence**
  - *Flow*: NaturalLanguage generates chapters with timestamps. User presses ⌘K, selects Chapter 2.
  - *Verification*: Player seeks to chapter start timestamp; chapter data is stored in database.

---

## 5. Tier 4: Real-World Application Scenarios (End-to-End User Workflows)

### Scenario 1: Live Dictation & Real-Time Note Generation (The "Executive Meeting" Flow)
- **User Persona**: Executive recording an in-person strategy meeting.
- **End-to-End Flow**:
  1. User activates quick recording via microphone button or global shortcut.
  2. Live audio meter visualizes speaker volume levels in real time.
  3. User speaks for 30 seconds across two distinct turns.
  4. User stops recording.
  5. Audio is auto-saved to disk and auto-transcribed via Whisper engine.
  6. Diarizer segments conversation into Speaker turns and assigns colored badges.
  7. Local NaturalLanguage generates bullet-point summary and action items.
  8. Full transcript, summary, and segments are atomically committed to `AppDatabase`.
  9. User clicks on second action item; player seeks to exact moment in audio ($ \pm 100$ms).
- **Verification Gates**:
  - Zero network activity throughout entire lifecycle (100% on-device).
  - Audio file is valid AAC/LPCM m4a.
  - Database contains consistent records across `job`, `transcript_section`, and `history`.
  - Seek accuracy is $\le 100$ms.

### Scenario 2: High-Paced Multi-Speaker Podcast Review & Editing (The "Editor" Flow)
- **User Persona**: Podcast producer reviewing a 2-speaker episode.
- **End-to-End Flow**:
  1. User imports a 5-minute `.m4a` podcast audio file via drag-and-drop.
  2. Accelerate/vDSP generates a 500-point normalized waveform in $<15$ms.
  3. Transcription finishes with word-level timestamps (`token_timestamps = true`).
  4. Waveform and karaoke transcript view render in synchronized split layout.
  5. User presses Spacebar to begin playback; words illuminate smoothly in karaoke style.
  6. User notices a misrecognized technical term at 02:14.50.
  7. User clicks the word: playback jumps immediately to $134.50 \pm 0.10$s.
  8. User pauses playback, edits the word inline in the rich editor.
  9. Database updates atomically in the background.
  10. User renames "Speaker 1" to "Host" and "Speaker 2" to "Guest".
  11. User presses ⌘E to export SRT subtitles; exported file contains updated text and speaker tags.
- **Verification Gates**:
  - Waveform generation completes in $< 15$ms.
  - Scrubbing and seeking maintain $\pm 100$ms synchronization.
  - Database reflects edited text without altering word timestamp spans.
  - Exported SRT file matches standard subtitle formatting with zero syntax errors.

### Scenario 3: YouTube Research Playlist Ingestion via Menu Bar Extra (The "Researcher" Flow)
- **User Persona**: Academic researcher collecting lectures from a YouTube playlist.
- **End-to-End Flow**:
  1. User copies a dirty text block containing multiple YouTube video URLs.
  2. User opens Menu Bar Companion and pastes the text.
  3. `URLParser` extracts, deduplicates, and validates all URLs.
  4. Batch assembler creates a new batch in `AppDatabase` with sequence order.
  5. For each video, cache is checked: 1 video already cached in `transcript_cache`, 2 are new.
  6. Cached video is instantly resolved from database without re-downloading.
  7. Remaining videos are downloaded, converted to 16kHz audio, and transcribed.
  8. If one video fails (e.g. HTTP 403), batch completes partially with detailed failure report.
  9. Final assembled markdown file is written atomically to output directory.
  10. User views transcript preview in Quick Look.
- **Verification Gates**:
  - Cached transcripts bypass duplicate computation.
  - Partial batch assembly succeeds with clear error reporting for failed jobs.
  - Output files are cleanly sanitized and numbered sequentially if collisions occur.

### Scenario 4: Fast Legal Deposition Dictation with Atomic Rollback (The "Legal" Flow)
- **User Persona**: Legal stenographer making rapid corrections during live testimony.
- **End-to-End Flow**:
  1. Audio file is ingested with strict confidentiality mandate.
  2. Transcript is loaded into inline editor.
  3. User makes 15 in-place corrections across different witness segments.
  4. System simulates unexpected simulated power loss / process kill during write.
  5. Database transaction rolls back cleanly; no corrupt or half-written sections remain.
  6. Upon app restart, crash recovery checks database integrity.
  7. User resumes editing; commits updates cleanly.
- **Verification Gates**:
  - SQLite WAL mode ensures atomic commit / rollback guarantees.
  - Zero data loss or corrupt strings in `transcript_section`.
  - Database schema integrity check (`PRAGMA integrity_check`) passes with "ok".

### Scenario 5: Headless Batch Pipeline via CLI with Zero Memory Leak (The "DevOps" Flow)
- **User Persona**: Automated ingestion worker running `transkripthub-cli`.
- **End-to-End Flow**:
  1. CLI launched in headless macOS environment with watched directory input.
  2. Ingests 50 diverse audio files (mp3, wav, m4a, caf).
  3. Validates audio formats via `AudioValidator`.
  4. Transcribes sequentially using Accelerate/vDSP and Metal GPU acceleration.
  5. Formats outputs to JSON and Markdown.
  6. Measures total process memory before and after batch.
- **Verification Gates**:
  - Peak memory usage remains $< 150$ MB.
  - No memory accumulation across files (zero leaks).
  - 100% exit code 0 on all valid files.

---

## 6. Test Suite Execution & Verification Guide

### 6.1 Runner Commands
```bash
# Run all unit, integration, and E2E test suites (100% pass)
swift test

# Run specifically the E2ETestSuite opaque-box tests
swift test --filter E2ETestSuite

# Run with verbose diagnostic output
swift test --verbose

# Run specific feature test suites
swift test --filter AudioPlaybackSeekSyncE2ETests
swift test --filter WaveformGeneratorE2ETests
swift test --filter AudioRecordingStateMachineE2ETests
swift test --filter SpeakerDiarizationE2ETests
swift test --filter AtomicDatabaseSyncE2ETests
swift test --filter ZeroRegressionE2ETests
```

### 6.2 Quality & Performance Assertion Thresholds
- **Existing Tests**: 39 / 39 passing cleanly (Zero Regressions).
- **Seek Accuracy**: $\le \pm 100$ms from target timestamp.
- **Waveform Generation**: $< 15$ms for 60 seconds of 16kHz audio.
- **Waveform Envelope Bounds**: $0.0 \le \text{min} \le \text{max} \le 1.0$ for all points.
- **Recording State Machine**: Strict sequential transition enforcement; zero illegal transitions.
- **Diarization Clustering**: Deterministic speaker separation and non-colliding badge assignment.
- **Database Atomicity**: 100% rollback guarantee on failed transactions; zero partial commits.
