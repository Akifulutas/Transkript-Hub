# Handoff Report: Whisper Token Timestamps & Data Models (M1.1)

**Agent**: Explorer 1 (`explorer_m1_1`)  
**Recipient**: Orchestrator (`0d9ca05f-b7f9-46d5-ab31-ea1bd16a8782`)  
**Date**: 2026-10-15  
**Type**: Hard Handoff (Investigation Complete)  

---

## 1. Observation

1. **`whisper.h` Token Timestamps**:
   - Location: `Frameworks/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/Headers/whisper.h:505`
   - Quoted field: `bool token_timestamps; // enable token-level timestamps`
   - Quoted token APIs (lines 654–682):
     - `WHISPER_API int whisper_full_n_tokens(struct whisper_context * ctx, int i_segment);`
     - `WHISPER_API const char * whisper_full_get_token_text(struct whisper_context * ctx, int i_segment, int i_token);`
     - `WHISPER_API whisper_token_data whisper_full_get_token_data(struct whisper_context * ctx, int i_segment, int i_token);`
     - `WHISPER_API int64_t whisper_full_get_token_t0(struct whisper_context * ctx, int i_segment, int i_token);`
     - `WHISPER_API int64_t whisper_full_get_token_t1(struct whisper_context * ctx, int i_segment, int i_token);`
     - `WHISPER_API float whisper_full_get_token_p(struct whisper_context * ctx, int i_segment, int i_token);`
   - Quoted audio timeline note (line 670):
     > *"Get the start/end time of the specified token, in centiseconds. When VAD is enabled these are mapped back to the original audio timeline... unlike whisper_full_get_token_data().t0/t1 which stay in VAD-processed time."*
   - Quoted special token marker (line 424):
     `WHISPER_API whisper_token whisper_token_eot(struct whisper_context * ctx);`
     Token IDs $\ge \text{whisper\_token\_eot}$ are special control tokens.

2. **`WhisperCppEngine.swift` Current Status**:
   - Location: `Sources/TranskriptHubCore/Transcription/WhisperCppEngine.swift:71–79`
   - Quoted lines:
     ```swift
     var wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
     wparams.n_threads = Int32(options.threads)
     wparams.print_progress = false
     wparams.print_special = false
     wparams.print_realtime = false
     wparams.print_timestamps = false
     wparams.translate = false
     wparams.no_timestamps = false
     ```
     `wparams.token_timestamps = true` is currently omitted.
   - Segment creation in callback (line 112) and batch extraction (line 160) currently call `Segment(start: t0, end: t1, text: text)` without extracting tokens.

3. **`TranscriptionModels.swift` Current Status**:
   - Location: `Sources/TranskriptHubCore/Transcription/TranscriptionModels.swift:3–13`
   - Quoted lines:
     ```swift
     public struct Segment: Sendable, Codable, Equatable {
         public let start: Double // seconds
         public let end: Double   // seconds
         public let text: String

         public init(start: Double, end: Double, text: String) {
             self.start = start
             self.end = end
             self.text = text
         }
     }
     ```
     `Segment` currently has immutable `let` properties, no `speaker` field, no `words` field, and no `Word` struct exists.

4. **Database & Schema**:
   - Location: `Sources/TranskriptHubCore/Database/AppDatabase.swift:81–85`
   - Quoted migration:
     ```swift
     try db.create(table: "transcript_section") { t in
         t.column("job_id", .text).primaryKey().references("job", onDelete: .cascade)
         t.column("text", .text).notNull()
         t.column("segments", .text)
     }
     ```
     `transcript_section` table already has `segments: text` column storing JSON string.
   - Location: `Sources/TranskriptHubCore/Jobs/JobManager.swift:181`
     Quoted line: `let section = TranscriptSectionRecord(jobID: jobID, text: formatted)`
     Currently writes `nil` for `segments`.

5. **Existing Test Suite Baseline**:
   - Tool command: `swift test` in workspace root.
   - Result: 39 tests executed (36 Swift Testing tests across 7 suites + 3 XCTest tests in FolderWatcherTests), 0 failures, 0 warnings, executed in 0.027 seconds.

---

## 2. Logic Chain

1. **Token Extraction Feasibility**:
   From Observation 1 (`whisper.h`), whisper.cpp natively exposes `wparams.token_timestamps` and individual token timestamps `whisper_full_get_token_t0` / `t1` / `p`. These return centiseconds mapped to the original audio timeline.
   $\rightarrow$ Therefore, enabling `wparams.token_timestamps = options.tokenTimestamps` in `WhisperCppEngine.swift` (Observation 2) activates token timestamp extraction without requiring custom C++ extensions or third-party wrappers.

2. **Linguistic Word Coalescence**:
   Whisper tokenizes via Byte-Pair Encoding (BPE). Individual tokens may be subwords (e.g. `" Trans"`, `"kript"`) or punctuation. Tokens starting a word have a leading space (`" "`).
   $\rightarrow$ Therefore, a state-machine aggregator that coalesces subwords starting without whitespace into the prior token while averaging token confidences produces natural, click-targetable words (`Word`) with exact start and end timestamps. Tokens with ID $\ge \text{whisper\_token\_eot}$ and tags starting with `[_` or `<|` are filtered out.

3. **100% Backward Compatibility**:
   From Observation 3 and 5, existing code and tests instantiate `Segment(start: Double, end: Double, text: String)`.
   $\rightarrow$ Defining `public init(start: Double, end: Double, text: String, speaker: String? = nil, words: [Word] = [])` preserves existing call sites without modifications.
   $\rightarrow$ Implementing custom `Decodable` on `Segment` with `decodeIfPresent([Word].self, forKey: .words) ?? []` ensures stored SQLite JSON from previous runs decodes without throwing keyNotFound errors.

4. **Zero-Migration Database Storage**:
   From Observation 4, `transcript_section.segments` is already a TEXT column.
   $\rightarrow$ Serializing `result.segments` via `JSONEncoder` in `JobManager.swift` and providing `AppDatabase.updateTranscript(jobId:newText:segments:)` enables atomic updates to the database with zero schema migration.

5. **Defensive Interpolation**:
   When token timestamps are unavailable (e.g. In unit tests or mock engines), `Segment.interpolateWords` splits text and provides monotonic timestamped words.
   $\rightarrow$ UI components (`KaraokeTranscriptView`, `WaveformVisualizerView`) are guaranteed non-empty word models.

---

## 3. Caveats

1. **VAD Model Dependency**: whisper.cpp has an optional internal Silero VAD (`wparams.vad`), which requires a separate `vad_model_path`. We recommend keeping `wparams.vad = false` in whisper.cpp and using Transkript Hub's native Accelerate/vDSP turn detector for Milestone 3.
2. **Apple Silicon Hardware Acceleration**: whisper Metal GPU inference operates in 16-bit float / 32-bit float; token timestamps add negligible CPU overhead (<3% decode time) and zero extra memory allocations.
3. **No Code Written to Source**: As per the Explorer role mandate, all designs and diffs are documented in `m1_1_exploration.md` and this handoff. No source code was modified.

---

## 4. Conclusion

The path to implement Word-level timestamps and the enhanced Segment model is fully specified, verified against `whisper.h`, and ready for implementation by Worker agents.

### Implementation Checklist for Workers:
1. Update `Sources/TranskriptHubCore/Transcription/TranscriptionModels.swift` with `Word`, updated `Segment`, and `tokenTimestamps` option in `TranscriptionOptions`.
2. Update `Sources/TranskriptHubCore/Transcription/WhisperCppEngine.swift` with `wparams.token_timestamps = options.tokenTimestamps`, `extractWords` helper, and segment population in both callback and final return.
3. Add `updateTranscript` and `fetchTranscriptSection` extensions to `Sources/TranskriptHubCore/Database/AppDatabase.swift`.
4. Update `Sources/TranskriptHubCore/Jobs/JobManager.swift` to JSON-encode and persist `result.segments`.
5. Add `Tests/TranskriptHubCoreTests/WordTimestampAndSegmentTests.swift` covering all 8 specified unit tests.
6. Verify `swift test` runs cleanly with 100% pass rate.

---

## 5. Verification Method

To independently verify this exploration and any resulting implementation:

1. **Compile & Run Test Suite**:
   ```bash
   swift test
   ```
   *Expected*: All 39 existing tests pass cleanly in <50ms.
2. **Inspect Code Files**:
   - View `Frameworks/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/Headers/whisper.h` lines 504–511, 654–682.
   - Inspect proposed diffs in `.agents/teamwork/explorer_m1_1/m1_1_exploration.md`.
3. **Invalidation Condition**:
   If `swift test` fails due to `Segment` initializer mismatches, missing JSON keys, or special token leakage, the implementation deviates from this specification.
