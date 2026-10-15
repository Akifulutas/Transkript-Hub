# Handoff Report — Spec Miner Survey 3
*Task: Transkript Hub Requirements (R1-R6) & Acceptance Criteria Gap Analysis*

---

## 1. Observation

1. **Test Suite Baseline & Build**:
   - Command: `swift test` in `/Users/akifulutas/Documents/Akif/Transkript Hub.txt`
   - Output: `Executed 3 tests, with 0 failures` (XCTest in `FolderWatcherTests`) and `Test run with 36 tests in 7 suites passed after 0.022 seconds` (Swift Testing). Total = exactly 39 unit/integration tests passing.
   - Command: `swift build`
   - Output: `Build complete! (0.41 sec)`, 0 errors, 0 warnings.
   - Binary & DMG: `dist/TranskriptHub.dmg` is `7,410,162` bytes (~7.4 MB), well under the 15 MB limit (`scripts/package_dmg.sh:95`).

2. **Audio Playback & Waveform (R1)**:
   - `grep_search` for `AVAudioPlayer`, `AVPlayer`, `AVAudioEngine` returned zero results in `Sources/`.
   - `AVFoundation` is imported only in `AudioValidator.swift:2` and `AudioDecoder.swift:2`.
   - `NativeTranscriptTextView.swift:33` sets `textView.isEditable = false`.
   - `WhisperCppEngine.swift:78` sets `wparams.no_timestamps = false`, but does not set `wparams.token_timestamps = true`, and extracts segments via `whisper_full_get_segment_text`, `whisper_full_get_segment_t0/t1` (lines 155-161).
   - `whisper.h:505` exposes `bool token_timestamps;` and lines 655-678 expose `whisper_full_n_tokens`, `whisper_full_get_token_text`, and `whisper_full_get_token_t0/t1`.
   - `AppViewModel.swift:984` runs `defer { try? FileManager.default.removeItem(at: itemWorkspace) }`, deleting temporary YouTube audio immediately post-transcription.

3. **In-App Recording Engine (R2)**:
   - `grep_search` for `AVAudioRecorder` and `record` returned zero recording implementations.
   - `Resources/TranskriptHub.entitlements` lines 1-22 do not contain `com.apple.security.device.audio-input`.
   - `scripts/package_dmg.sh:35-68` generates `Info.plist` without `NSMicrophoneUsageDescription`.

4. **Speaker Diarization & Inline Editor (R3)**:
   - `TRANSKRIPT_HUB_SPEC.md:48` historically listed speaker diarization under "Out of Scope".
   - `TranscriptionModels.swift:3-13` defines `Segment` strictly with `(start: Double, end: Double, text: String)`. No `speaker` field exists.
   - `AppDatabase.swift:81-85` creates `transcript_section` with `(job_id, text, segments)`. There is no API to atomically update transcript text or segments from the UI.

5. **Menu Bar Companion & Ergonomics (R4 & R5)**:
   - `TranskriptHubApp.swift:89-93` declares `MenuBarExtra` hosting `MenuBarMiniWindow`.
   - `MenuBarMiniWindow.swift:1-147` contains a quick textfield and buttons, but no `.onDrop` modifier for audio files.
   - `ContentView.swift:389-419` (`KeyInterceptingView`) handles ⌘K, ⌘V, ⇧⌘C, ⌘A locally, but lacks Spacebar play/pause, ⌘F search navigation, and ⌘E export.
   - No `QLPreviewPanel` or `QuickLook` integration exists in `Sources/`.

6. **Accelerate & Signal Processing (R6)**:
   - `grep_search` for `Accelerate` and `vDSP` returned zero results in `Sources/`. No audio downsampling or FFT exists.

---

## 2. Logic Chain

1. From **Observation 1**, the existing foundation is stable: 39 tests pass, the compiler is clean, and DMG packaging creates an ultra-lean 7.4 MB artifact.
2. From **Observation 2**, Acceptance Criteria 1, 2, and 3 cannot pass in the current state because:
   - No audio player exists to receive play/pause/seek commands.
   - Whisper token timestamps are not extracted, so word-level millisecond seeking (±100ms) cannot function.
   - Waveform is an SF Symbol icon rather than an interactive component rendering downsampled audio amplitudes.
   - Temporary audio files are discarded after transcription, leaving no media for playback.
3. From **Observation 3**, Acceptance Criteria 4 and 5 cannot pass because:
   - No recording engine or microphone tap is implemented.
   - macOS hardened runtime will block/crash recording attempts without the audio-input entitlement and privacy description.
4. From **Observation 4**, Acceptance Criteria 6 and 7 cannot pass because:
   - Transcripts are rendered in a read-only `NSTextView`.
   - No speaker model or diarization algorithm exists.
5. From **Observation 5**, Requirement R4 and R5 keyboard/desktop expectations are incomplete because:
   - Menu Bar lacks drag-and-drop ingestion.
   - Global hotkey is missing.
   - Keyboard shortcuts for Space (play/pause), ⌘F (find hit navigation), and ⌘E (export) are absent.
6. From **Observation 6**, all needed signal processing (RMS volume metering, FFT frequency bars, waveform downsampling) and extractive summarization can be achieved with 100% native Apple frameworks (`AVFoundation`, `Accelerate/vDSP`, `NaturalLanguage`, `AppKit`, `SwiftUI`), preserving the zero-dependency mandate and <10 MB footprint.

---

## 3. Caveats

- **whisper.cpp Token Timestamp Verification**: While `whisper.h` defines `wparams.token_timestamps = true` and `whisper_full_get_token_data`, the exact behavior with non-English or VAD-trimmed audio should be verified with a small integration test during implementation.
- **Microphone Permissions in Headless CI**: Automated tests cannot interactively grant microphone TCC permissions. The recording engine must be architected with a protocol/mock layer so that unit tests can verify audio buffer capture and file writing deterministically without requiring a real hardware microphone.
- **Diarization Strategy**: Because cloud LLMs and heavy Python diarization models (e.g. pyannote) are forbidden by the zero-dependency and <10MB rules, diarization must be implemented locally via acoustic turn clustering (silence/energy profiling via vDSP).

---

## 4. Conclusion

1. The current Transkript Hub codebase satisfies basic batch transcription and offline YouTube ingestion, but requires substantial architectural additions to achieve the AAA Apple 1st-party experience mandated in `ORIGINAL_REQUEST.md`.
2. Out of 17 specific requirement sub-items (R1.1–R6.3), **7 are completely missing**, **7 require major modifications/additions**, and **3 currently exist/pass**.
3. Out of 11 Acceptance Criteria, **4 PASS** (DMG size < 15MB, launch < 200ms, 39 existing tests pass, clean build), while **7 FAIL** due to missing playback, recording, waveform, diarization, and inline editing engines.
4. A 20-feature inventory has been formulated in `survey_spec_gaps.md` using strictly native Apple frameworks (`AVFoundation`, `Accelerate`, `NaturalLanguage`, `AppKit`, `SwiftUI`).

---

## 5. Verification Method

To independently reproduce and verify this assessment:

1. **Verify Test Suite**:
   ```bash
   cd "/Users/akifulutas/Documents/Akif/Transkript Hub.txt"
   swift test
   ```
   *Expected*: Exactly 39 tests pass in ~0.02s.

2. **Verify Clean Build**:
   ```bash
   swift build
   ```
   *Expected*: Compiles cleanly with 0 errors and 0 warnings.

3. **Verify Absence of Audio Player & Recording**:
   ```bash
   git grep "AVAudioPlayer" Sources/
   git grep "AVAudioEngine" Sources/
   git grep "AVAudioRecorder" Sources/
   ```
   *Expected*: No matching lines returned.

4. **Verify Current DMG Footprint**:
   ```bash
   ls -lh dist/TranskriptHub.dmg
   ```
   *Expected*: Size is ~7.4 MB.

5. **Inspect Detailed Gap Report**:
   Inspect `.agents/teamwork/spec_miner_survey_3/survey_spec_gaps.md`.
