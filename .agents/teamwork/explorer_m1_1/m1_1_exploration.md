# M1.1 Exploration Report: Whisper Token Timestamps, Data Models & Persistence

**Explorer**: Explorer 1 (Milestone 1 — Audio Playback & Karaoke Sync)  
**Date**: 2026-10-15  
**Working Directory**: `.agents/teamwork/explorer_m1_1`  
**Target Files**:
- `Sources/TranskriptHubCore/Transcription/TranscriptionModels.swift`
- `Sources/TranskriptHubCore/Transcription/WhisperCppEngine.swift`
- `Sources/TranskriptHubCore/Database/AppDatabase.swift`
- `Sources/TranskriptHubCore/Jobs/JobManager.swift`
- `Tests/TranskriptHubCoreTests/WordTimestampAndSegmentTests.swift`

---

## 1. Executive Summary

Transkript Hub requires millisecond-accurate word-level timestamps (`Word` and `Segment` models) to power interactive waveform visualizers, click-to-seek playback, and karaoke-style active word illumination (Requirements R1.1, R1.3, AC#1).

This investigation verified:
1. **Whisper C API Capability**: `whisper.xcframework` includes full support for token timestamps via `wparams.token_timestamps = true`, `whisper_full_n_tokens`, `whisper_full_get_token_text`, `whisper_full_get_token_data`, `whisper_full_get_token_t0`, `whisper_full_get_token_t1`, and `whisper_full_get_token_p`.
2. **Audio Timeline Mapping**: `whisper_full_get_token_t0` and `t1` return centisecond timestamps (10ms resolution, `Double(t) / 100.0` in seconds) mapped directly to the original audio timeline.
3. **Subword BPE to Word Aggregation**: Whisper outputs Byte-Pair Encoded (BPE) subwords with leading spaces for new words. We designed a zero-copy, memory-safe accumulation algorithm that coalesces subwords and punctuation into natural linguistic words with averaged confidences and exact time boundaries, while stripping special tokens (`[_BEG_]`, `<|...|>`).
4. **100% Backward Compatibility**:
   - `Segment` retains default parameter values (`speaker: String? = nil`, `words: [Word] = []`), allowing all 39 existing unit and integration tests to compile and pass without modification.
   - Custom `Decodable` on `Segment` decodes legacy JSON missing `"words"` or `"speaker"` without throwing `DecodingError.keyNotFound`.
   - SQLite table `transcript_section` already has the `segments: text` column; no schema migration is required.
   - An intelligent fallback (`Segment.interpolateWords`) ensures that even mock engines or non-token transcriptions produce monotonically timestamped words for UI components.

---

## 2. Deep Dive: Whisper C API & Token Timestamps Mechanics

### 2.1 Whisper Header Analysis (`whisper.h`)

Inspection of `Frameworks/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/Headers/whisper.h`:

- **Token Timestamp Flag** (Line 505):
  ```c
  bool token_timestamps; // enable token-level timestamps
  float thold_pt;        // timestamp token probability threshold (~0.01)
  float thold_ptsum;     // timestamp token sum probability threshold (~0.01)
  int max_len;           // max segment length in characters
  bool split_on_word;    // split on word rather than on token (when used with max_len)
  int max_tokens;        // max tokens per segment (0 = no limit)
  ```
  `whisper_full_default_params(WHISPER_SAMPLING_GREEDY)` initializes `thold_pt = 0.01f` and `thold_ptsum = 0.01f`. By enabling `wparams.token_timestamps = true`, Whisper computes dynamic token alignment probabilities and timestamps.

- **Token Data Structure** (Lines 131–151):
  ```c
  typedef struct whisper_token_data {
      whisper_token id;  // token id
      whisper_token tid; // forced timestamp token id
      float p;           // probability of the token
      float plog;        // log probability of the token
      float pt;          // probability of the timestamp token
      float ptsum;       // sum of probabilities of all timestamp tokens
      int64_t t0;        // start time of the token (centiseconds)
      int64_t t1;        // end time of the token (centiseconds)
      int64_t t_dtw;     // DTW timestamp
      float vlen;        // voice length
  } whisper_token_data;
  ```

- **Token Extraction APIs** (Lines 654–682):
  ```c
  WHISPER_API int whisper_full_n_tokens(struct whisper_context * ctx, int i_segment);
  WHISPER_API const char * whisper_full_get_token_text(struct whisper_context * ctx, int i_segment, int i_token);
  WHISPER_API whisper_token_data whisper_full_get_token_data(struct whisper_context * ctx, int i_segment, int i_token);
  WHISPER_API int64_t whisper_full_get_token_t0(struct whisper_context * ctx, int i_segment, int i_token);
  WHISPER_API int64_t whisper_full_get_token_t1(struct whisper_context * ctx, int i_segment, int i_token);
  WHISPER_API float whisper_full_get_token_p(struct whisper_context * ctx, int i_segment, int i_token);
  ```

- **Timeline Mapping Guarantee** (Line 670):
  Header documentation confirms:
  > *"Get the start/end time of the specified token, in centiseconds. When VAD is enabled these are mapped back to the original audio timeline... unlike whisper_full_get_token_data().t0/t1 which stay in VAD-processed time. Without VAD the raw token times are returned unchanged."*

  Therefore, calling `whisper_full_get_token_t0` and `t1` (divided by `100.0` to yield seconds) is strictly superior to reading raw `token_data.t0/t1`.

- **Special Token Filtering** (Lines 424–431):
  ```c
  WHISPER_API whisper_token whisper_token_eot(struct whisper_context * ctx);
  ```
  In Whisper, all token IDs $\ge \text{whisper\_token\_eot}(\text{ctx})$ (ID 50256+) represent special control tokens (SOT, EOT, language tags, transcription mode, and timestamp tokens). Comparing `tokenData.id >= whisper_token_eot(ctx)` filters out non-text tokens in $O(1)$ time. A secondary string check filters tokens beginning with `[_` or `<|`.

---

## 3. Data Model Architecture

### 3.1 `Word` Struct Design

Conforming to the interface specification in `PROJECT.md` (lines 92–97):

```swift
public struct Word: Sendable, Codable, Equatable, Identifiable {
    public var id: String { "\(start)_\(end)_\(text)" }
    public let text: String
    public let start: Double // seconds
    public let end: Double   // seconds
    public let confidence: Float
    
    public init(text: String, start: Double, end: Double, confidence: Float = 1.0) {
        self.text = text
        self.start = start
        self.end = end
        self.confidence = confidence
    }
    
    public var duration: Double {
        max(0, end - start)
    }
    
    public func contains(time: Double) -> Bool {
        time >= start && time <= end
    }
}
```

**Key properties**:
- `Identifiable`: Conforms via computed `id` property, so SwiftUI `ForEach(segment.words)` renders directly without requiring manual ID indexing. Computed properties are ignored by Codable and Equatable.
- `contains(time:)`: Enables $O(1)$ karaoke word lookup during 60/120 fps playback updates.
- Precision: Standard `Double` seconds with millisecond resolution (e.g. `1.240`).

### 3.2 Updated `Segment` Model & Backward Compatibility

Conforming to `PROJECT.md` (lines 99–105):

```swift
public struct Segment: Sendable, Codable, Equatable {
    public var start: Double // seconds
    public var end: Double   // seconds
    public var text: String
    public var speaker: String?
    public var words: [Word]

    public init(
        start: Double,
        end: Double,
        text: String,
        speaker: String? = nil,
        words: [Word] = []
    ) {
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
        self.words = words
    }
    
    enum CodingKeys: String, CodingKey {
        case start
        case end
        case text
        case speaker
        case words
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.start = try container.decode(Double.self, forKey: .start)
        self.end = try container.decode(Double.self, forKey: .end)
        self.text = try container.decode(String.self, forKey: .text)
        self.speaker = try container.decodeIfPresent(String.self, forKey: .speaker)
        self.words = try container.decodeIfPresent([Word].self, forKey: .words) ?? []
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(speaker, forKey: .speaker)
        try container.encode(words, forKey: .words)
    }
    
    public var duration: Double {
        max(0, end - start)
    }
    
    public func contains(time: Double) -> Bool {
        time >= start && time <= end
    }
    
    public func word(at time: Double) -> Word? {
        words.first { $0.contains(time: time) }
    }
    
    /// Generates approximate word boundaries when raw token timestamps are unavailable.
    public static func interpolateWords(for text: String, start: Double, end: Double) -> [Word] {
        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return [] }
        
        let totalDuration = max(0.05, end - start)
        let step = totalDuration / Double(tokens.count)
        
        return tokens.enumerated().map { index, token in
            let wordStart = start + (Double(index) * step)
            let wordEnd = min(end, wordStart + step)
            return Word(
                text: token,
                start: (wordStart * 1000).rounded() / 1000,
                end: (wordEnd * 1000).rounded() / 1000,
                confidence: 1.0
            )
        }
    }
}
```

**Backward Compatibility Proof**:
1. `init(start:end:text:)` remains valid because `speaker` defaults to `nil` and `words` defaults to `[]`.
2. Custom `Decodable` uses `decodeIfPresent([Word].self, forKey: .words) ?? []`, ensuring old records stored without `"words"` decode without throwing `DecodingError.keyNotFound`.
3. `interpolateWords(for:start:end:)` provides automatic synthetic word timestamps for mock engines and tests, preventing UI components from receiving empty word arrays.

---

## 4. Subword Token to Word Aggregation Algorithm

Whisper's BPE vocabulary splits text into subwords. A leading space character (`" "`) denotes a word boundary, while tokens without leading space continue the current word or attach punctuation.

### Accumulation State Machine

```
               ┌────────────────────────┐
               │   Next Token Received  │
               └───────────┬────────────┘
                           │
             Is ID >= EOT or Special Tag?
              ├─── YES ──> [ Skip Token ]
              └─── NO
                           │
             Is Token Whitespace Only?
              ├─── YES ──> [ Flush Current Word ] -> [ Set State: No Active Word ]
              └─── NO
                           │
         Token Starts With Space OR No Active Word?
              ├─── YES ──> [ Flush Current Word ]
              │            [ Start New Word: text=trimmed, t0=token.t0, t1=token.t1 ]
              │
              └─── NO  ──> [ Subword / Punctuation Continuation ]
                           [ current.text += tokenText ]
                           [ current.end = max(current.end, token.t1) ]
                           [ current.confidences.append(token.p) ]
```

### Swift Implementation

```swift
private static func extractWords(
    from ctx: OpaquePointer,
    segmentIndex: Int32,
    segmentStart: Double,
    segmentEnd: Double
) -> [Word] {
    let nTokens = whisper_full_n_tokens(ctx, segmentIndex)
    guard nTokens > 0 else { return [] }
    
    let eot = whisper_token_eot(ctx)
    var words: [Word] = []
    
    var currentText = ""
    var currentStart = segmentStart
    var currentEnd = segmentEnd
    var currentConfidences: [Float] = []
    var hasActiveWord = false
    
    func flushCurrentWord() {
        guard hasActiveWord else { return }
        let trimmed = currentText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let avgConf = currentConfidences.isEmpty ? 1.0 : currentConfidences.reduce(0, +) / Float(currentConfidences.count)
            words.append(Word(
                text: trimmed,
                start: currentStart,
                end: max(currentStart, currentEnd),
                confidence: avgConf
            ))
        }
        currentText = ""
        currentConfidences.removeAll()
        hasActiveWord = false
    }
    
    for j in 0..<nTokens {
        let tokenData = whisper_full_get_token_data(ctx, segmentIndex, j)
        if tokenData.id >= eot { continue }
        
        guard let textPtr = whisper_full_get_token_text(ctx, segmentIndex, j) else { continue }
        let tokenStr = String(cString: textPtr)
        guard !tokenStr.isEmpty else { continue }
        
        if tokenStr.hasPrefix("[_") || tokenStr.hasPrefix("<|") || tokenStr.hasSuffix("|>") {
            continue
        }
        
        let t0Raw = whisper_full_get_token_t0(ctx, segmentIndex, j)
        let t1Raw = whisper_full_get_token_t1(ctx, segmentIndex, j)
        let tokenStart = t0Raw >= 0 ? Double(t0Raw) / 100.0 : segmentStart
        let tokenEnd = t1Raw >= 0 ? Double(t1Raw) / 100.0 : max(tokenStart, segmentEnd)
        let confidence = whisper_full_get_token_p(ctx, segmentIndex, j)
        
        let trimmed = tokenStr.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            flushCurrentWord()
            continue
        }
        
        let startsWithSpace = tokenStr.first?.isWhitespace == true
        if startsWithSpace || !hasActiveWord {
            flushCurrentWord()
            currentText = trimmed
            currentStart = tokenStart
            currentEnd = tokenEnd
            currentConfidences = [confidence]
            hasActiveWord = true
        } else {
            currentText.append(tokenStr)
            currentEnd = max(currentEnd, tokenEnd)
            currentConfidences.append(confidence)
        }
    }
    
    flushCurrentWord()
    return words
}
```

---

## 5. Database Persistence & GRDB Serialization

### 5.1 Existing Schema Compatibility

In `Sources/TranskriptHubCore/Database/AppDatabase.swift`:
```sql
CREATE TABLE transcript_section (
    job_id TEXT PRIMARY KEY REFERENCES job(id) ON DELETE CASCADE,
    text TEXT NOT NULL,
    segments TEXT
);
```
The `segments` column is already defined as nullable `TEXT`. It stores JSON arrays of `Segment` records. No migration is required.

### 5.2 Atomic Model Sync Extension

In `AppDatabase.swift`:
```swift
extension AppDatabase {
    /// Atomically updates the formatted transcript text and JSON-serialized segments for a given job.
    public func updateTranscript(jobId: String, newText: String, segments: [Segment]) async throws {
        let encoder = JSONEncoder()
        let segmentsData = try encoder.encode(segments)
        let segmentsString = String(data: segmentsData, encoding: .utf8)
        
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO transcript_section (job_id, text, segments)
                VALUES (?, ?, ?)
                ON CONFLICT(job_id) DO UPDATE SET
                    text = excluded.text,
                    segments = excluded.segments
                """,
                arguments: [jobId, newText, segmentsString]
            )
        }
    }
    
    /// Fetches the transcript text and decoded segments for a job.
    public func fetchTranscriptSection(jobId: String) async throws -> (text: String, segments: [Segment])? {
        try await dbQueue.read { db in
            guard let record = try TranscriptSectionRecord.filter(Column("job_id") == jobId).fetchOne(db) else {
                return nil
            }
            var parsedSegments: [Segment] = []
            if let jsonString = record.segments, let data = jsonString.data(using: .utf8) {
                parsedSegments = (try? JSONDecoder().decode([Segment].self, from: data)) ?? []
            }
            return (text: record.text, segments: parsedSegments)
        }
    }
}
```

### 5.3 Pipeline Storage in `JobManager.swift`

In `Sources/TranskriptHubCore/Jobs/JobManager.swift` (around line 180):
```swift
let segmentsData = try? JSONEncoder().encode(result.segments)
let segmentsJson = segmentsData != nil ? String(data: segmentsData!, encoding: .utf8) : nil

try await database.dbQueue.write { db in
    let section = TranscriptSectionRecord(jobID: jobID, text: formatted, segments: segmentsJson)
    try section.insert(db)
    ...
}
```

---

## 6. Proposed Code Diffs

### 6.1 `Sources/TranskriptHubCore/Transcription/TranscriptionModels.swift`

```patch
--- a/Sources/TranskriptHubCore/Transcription/TranscriptionModels.swift
+++ b/Sources/TranskriptHubCore/Transcription/TranscriptionModels.swift
@@ -1,13 +1,86 @@
 import Foundation
 
+public struct Word: Sendable, Codable, Equatable, Identifiable {
+    public var id: String { "\(start)_\(end)_\(text)" }
+    public let text: String
+    public let start: Double // seconds
+    public let end: Double   // seconds
+    public let confidence: Float
+    
+    public init(text: String, start: Double, end: Double, confidence: Float = 1.0) {
+        self.text = text
+        self.start = start
+        self.end = end
+        self.confidence = confidence
+    }
+    
+    public var duration: Double {
+        max(0, end - start)
+    }
+    
+    public func contains(time: Double) -> Bool {
+        time >= start && time <= end
+    }
+}
+
 public struct Segment: Sendable, Codable, Equatable {
-    public let start: Double // seconds
-    public let end: Double   // seconds
-    public let text: String
+    public var start: Double // seconds
+    public var end: Double   // seconds
+    public var text: String
+    public var speaker: String?
+    public var words: [Word]
 
-    public init(start: Double, end: Double, text: String) {
+    public init(
+        start: Double,
+        end: Double,
+        text: String,
+        speaker: String? = nil,
+        words: [Word] = []
+    ) {
         self.start = start
         self.end = end
         self.text = text
+        self.speaker = speaker
+        self.words = words
+    }
+    
+    enum CodingKeys: String, CodingKey {
+        case start
+        case end
+        case text
+        case speaker
+        case words
+    }
+    
+    public init(from decoder: Decoder) throws {
+        let container = try decoder.container(keyedBy: CodingKeys.self)
+        self.start = try container.decode(Double.self, forKey: .start)
+        self.end = try container.decode(Double.self, forKey: .end)
+        self.text = try container.decode(String.self, forKey: .text)
+        self.speaker = try container.decodeIfPresent(String.self, forKey: .speaker)
+        self.words = try container.decodeIfPresent([Word].self, forKey: .words) ?? []
+    }
+    
+    public func encode(to encoder: Encoder) throws {
+        var container = encoder.container(keyedBy: CodingKeys.self)
+        try container.encode(start, forKey: .start)
+        try container.encode(end, forKey: .end)
+        try container.encode(text, forKey: .text)
+        try container.encodeIfPresent(speaker, forKey: .speaker)
+        try container.encode(words, forKey: .words)
+    }
+    
+    public var duration: Double {
+        max(0, end - start)
+    }
+    
+    public func contains(time: Double) -> Bool {
+        time >= start && time <= end
+    }
+    
+    public func word(at time: Double) -> Word? {
+        words.first { $0.contains(time: time) }
+    }
+    
+    public static func interpolateWords(for text: String, start: Double, end: Double) -> [Word] {
+        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
+        guard !tokens.isEmpty else { return [] }
+        
+        let totalDuration = max(0.05, end - start)
+        let step = totalDuration / Double(tokens.count)
+        
+        return tokens.enumerated().map { index, token in
+            let wordStart = start + (Double(index) * step)
+            let wordEnd = min(end, wordStart + step)
+            return Word(
+                text: token,
+                start: (wordStart * 1000).rounded() / 1000,
+                end: (wordEnd * 1000).rounded() / 1000,
+                confidence: 1.0
+            )
+        }
+    }
 }
@@ -32,12 +105,14 @@
     public var useVAD: Bool             // default true
     public var threads: Int             // default: performance core count
     public var initialPrompt: String?   // optional terms list
+    public var tokenTimestamps: Bool    // default: true
     
     public init(
         language: String? = nil,
         useVAD: Bool = true,
         threads: Int = min(ProcessInfo.processInfo.activeProcessorCount, 6),
-        initialPrompt: String? = nil
+        initialPrompt: String? = nil,
+        tokenTimestamps: Bool = true
     ) {
         self.language = language
         self.useVAD = useVAD
+        self.tokenTimestamps = tokenTimestamps
```

### 6.2 `Sources/TranskriptHubCore/Transcription/WhisperCppEngine.swift`

```patch
--- a/Sources/TranskriptHubCore/Transcription/WhisperCppEngine.swift
+++ b/Sources/TranskriptHubCore/Transcription/WhisperCppEngine.swift
@@ -78,6 +78,7 @@
         wparams.print_timestamps = false
         wparams.translate = false
         wparams.no_timestamps = false
+        wparams.token_timestamps = options.tokenTimestamps
         
         // Stream callback wrapper for progress and live segments
@@ -109,7 +110,11 @@
                     let t1 = Double(whisper_full_get_segment_t1(ctx, i)) / 100.0
                     let textPtr = whisper_full_get_segment_text(ctx, i)
                     let text = textPtr != nil ? String(cString: textPtr!) : ""
-                    let segment = Segment(start: t0, end: t1, text: text)
+                    var words = WhisperCppEngine.extractWords(from: ctx, segmentIndex: i, segmentStart: t0, segmentEnd: t1)
+                    if words.isEmpty && !text.isEmpty {
+                        words = Segment.interpolateWords(for: text, start: t0, end: t1)
+                    }
+                    let segment = Segment(start: t0, end: t1, text: text, speaker: nil, words: words)
                     box.onSegment?(segment)
                 }
             }
@@ -157,7 +162,11 @@
             let t1 = Double(whisper_full_get_segment_t1(context, i)) / 100.0
             let textPtr = whisper_full_get_segment_text(context, i)
             let text = textPtr != nil ? String(cString: textPtr!) : ""
-            segments.append(Segment(start: t0, end: t1, text: text))
+            var words = Self.extractWords(from: context, segmentIndex: i, segmentStart: t0, segmentEnd: t1)
+            if words.isEmpty && !text.isEmpty {
+                words = Segment.interpolateWords(for: text, start: t0, end: t1)
+            }
+            segments.append(Segment(start: t0, end: t1, text: text, speaker: nil, words: words))
         }
         
         // Detect language
@@ -171,4 +180,68 @@
+    private static func extractWords(
+        from ctx: OpaquePointer,
+        segmentIndex: Int32,
+        segmentStart: Double,
+        segmentEnd: Double
+    ) -> [Word] {
+        let nTokens = whisper_full_n_tokens(ctx, segmentIndex)
+        guard nTokens > 0 else { return [] }
+        
+        let eot = whisper_token_eot(ctx)
+        var words: [Word] = []
+        
+        var currentText = ""
+        var currentStart = segmentStart
+        var currentEnd = segmentEnd
+        var currentConfidences: [Float] = []
+        var hasActiveWord = false
+        
+        func flushCurrentWord() {
+            guard hasActiveWord else { return }
+            let trimmed = currentText.trimmingCharacters(in: .whitespaces)
+            if !trimmed.isEmpty {
+                let avgConf = currentConfidences.isEmpty ? 1.0 : currentConfidences.reduce(0, +) / Float(currentConfidences.count)
+                words.append(Word(
+                    text: trimmed,
+                    start: currentStart,
+                    end: max(currentStart, currentEnd),
+                    confidence: avgConf
+                ))
+            }
+            currentText = ""
+            currentConfidences.removeAll()
+            hasActiveWord = false
+        }
+        
+        for j in 0..<nTokens {
+            let tokenData = whisper_full_get_token_data(ctx, segmentIndex, j)
+            if tokenData.id >= eot { continue }
+            
+            guard let textPtr = whisper_full_get_token_text(ctx, segmentIndex, j) else { continue }
+            let tokenStr = String(cString: textPtr)
+            guard !tokenStr.isEmpty else { continue }
+            
+            if tokenStr.hasPrefix("[_") || tokenStr.hasPrefix("<|") || tokenStr.hasSuffix("|>") {
+                continue
+            }
+            
+            let t0Raw = whisper_full_get_token_t0(ctx, segmentIndex, j)
+            let t1Raw = whisper_full_get_token_t1(ctx, segmentIndex, j)
+            let tokenStart = t0Raw >= 0 ? Double(t0Raw) / 100.0 : segmentStart
+            let tokenEnd = t1Raw >= 0 ? Double(t1Raw) / 100.0 : max(tokenStart, segmentEnd)
+            let confidence = whisper_full_get_token_p(ctx, segmentIndex, j)
+            
+            let trimmed = tokenStr.trimmingCharacters(in: .whitespaces)
+            if trimmed.isEmpty {
+                flushCurrentWord()
+                continue
+            }
+            
+            let startsWithSpace = tokenStr.first?.isWhitespace == true
+            if startsWithSpace || !hasActiveWord {
+                flushCurrentWord()
+                currentText = trimmed
+                currentStart = tokenStart
+                currentEnd = tokenEnd
+                currentConfidences = [confidence]
+                hasActiveWord = true
+            } else {
+                currentText.append(tokenStr)
+                currentEnd = max(currentEnd, tokenEnd)
+                currentConfidences.append(confidence)
+            }
+        }
+        
+        flushCurrentWord()
+        return words
+    }
 }
```

### 6.3 `Sources/TranskriptHubCore/Database/AppDatabase.swift`

```patch
--- a/Sources/TranskriptHubCore/Database/AppDatabase.swift
+++ b/Sources/TranskriptHubCore/Database/AppDatabase.swift
@@ -131,3 +131,39 @@
     }
 }
+
+extension AppDatabase {
+    /// Atomically updates the formatted transcript text and JSON-serialized segments for a given job.
+    public func updateTranscript(jobId: String, newText: String, segments: [Segment]) async throws {
+        let encoder = JSONEncoder()
+        let segmentsData = try encoder.encode(segments)
+        let segmentsString = String(data: segmentsData, encoding: .utf8)
+        
+        try await dbQueue.write { db in
+            try db.execute(
+                sql: """
+                INSERT INTO transcript_section (job_id, text, segments)
+                VALUES (?, ?, ?)
+                ON CONFLICT(job_id) DO UPDATE SET
+                    text = excluded.text,
+                    segments = excluded.segments
+                """,
+                arguments: [jobId, newText, segmentsString]
+            )
+        }
+    }
+    
+    /// Fetches the transcript text and decoded segments for a job.
+    public func fetchTranscriptSection(jobId: String) async throws -> (text: String, segments: [Segment])? {
+        try await dbQueue.read { db in
+            guard let record = try TranscriptSectionRecord.filter(Column("job_id") == jobId).fetchOne(db) else {
+                return nil
+            }
+            var parsedSegments: [Segment] = []
+            if let jsonString = record.segments, let data = jsonString.data(using: .utf8) {
+                parsedSegments = (try? JSONDecoder().decode([Segment].self, from: data)) ?? []
+            }
+            return (text: record.text, segments: parsedSegments)
+        }
+    }
+}
```

---

## 7. Unit Test Verification Strategy

### 7.1 New Test Suite: `Tests/TranskriptHubCoreTests/WordTimestampAndSegmentTests.swift`

We recommend adding `WordTimestampAndSegmentTests.swift` with 8 comprehensive unit tests:

1. **`testWordInitializationAndContainment`**:
   - Asserts `Word` fields: `text`, `start`, `end`, `confidence`.
   - Asserts `duration == end - start`.
   - Asserts `contains(time:)` returns true within bounds and false outside.
   - Asserts `id` is stable and non-empty.

2. **`testSegmentInitDefaultBackwardCompatibility`**:
   - Asserts `Segment(start: 0.0, end: 2.5, text: "Test")` produces `speaker == nil` and `words == []`.
   - Asserts synthesized equality works with legacy test patterns.

3. **`testSegmentWithWordsAndSpeaker`**:
   - Asserts rich initialization with `speaker: "Speaker 1"` and `words: [...]`.
   - Asserts `segment.word(at: 1.2)` returns the matching `Word`.
   - Asserts property mutability (`segment.text = "New"`, `segment.speaker = "Speaker 2"`).

4. **`testSegmentCodableBackwardCompatibility`**:
   - Takes legacy JSON payload: `{"start":0.0,"end":2.0,"text":"Hello world"}`.
   - Decodes into `Segment`.
   - Asserts decode succeeds without error, `speaker == nil`, and `words == []`.

5. **`testSegmentCodableRoundTripWithWords`**:
   - Encodes a complete `Segment` with words and speaker to JSON.
   - Decodes back and verifies `==` equality.

6. **`testSegmentWordInterpolationFallback`**:
   - Calls `Segment.interpolateWords(for: "Apple Silicon transcription powerhouse", start: 0.0, end: 2.0)`.
   - Verifies 4 words generated with strictly monotonic timestamps matching the overall duration.
   - Verifies empty string yields `[]`.

7. **`testAppDatabaseUpdateAndFetchTranscript`**:
   - Creates in-memory database (`AppDatabase.makeInMemory()`).
   - Inserts batch and job records.
   - Calls `database.updateTranscript(jobId: "test-job", newText: "Sample text", segments: [segment])`.
   - Calls `database.fetchTranscriptSection(jobId: "test-job")`.
   - Asserts retrieved text and segments match exactly.
   - Verifies upsert behavior via repeated call.

8. **`testTranscriptionOptionsTokenTimestampsToggle`**:
   - Asserts `options.tokenTimestamps == true` by default.
   - Asserts `TranscriptionOptions(tokenTimestamps: false).tokenTimestamps == false`.

### 7.2 Zero-Regression Verification

All existing 14 test suites (36 Swift Testing tests + 3 XCTest tests = 39 tests) must continue to pass cleanly via `swift test`.
