# Transkript Hub 🎙️⚡

<p align="center">
  <a href="https://github.com/Akifulutas/Transkript-Hub/releases/latest/download/TranskriptHub.dmg">
    <img src="https://img.shields.io/badge/📥_Download_Transkript_Hub-macOS_(Apple_Silicon)-007AFF?style=for-the-badge&logo=apple&logoColor=white" alt="Download Transkript Hub for macOS">
  </a>
  <br>
  <sub>⚡ 1-Click Install • Apple Silicon (M1/M2/M3/M4) • Zero Python / External Dependencies • 100% Offline Maximum Accuracy</sub>
</p>

**Fully Local, Offline, Maximum-Accuracy Audio & Video Transcription Studio for Apple Silicon Macs.**

Transkript Hub transcribes local audio and video recordings (Voice Memos, M4A, MP3, WAV, AAC, FLAC, OGG, Opus, WMA, MP4, MOV, MKV, WebM) and YouTube content (single videos, playlists, channels) into plain text (`.txt`) and SubRip (`.srt`) subtitles directly on your Mac's Apple Silicon hardware (**Metal GPU + Apple Accelerate BLAS / vDSP**) — sending **zero bytes to external servers**.

---

## ✨ Features

- **👑 Dual-Engine Maximum-Accuracy Architecture:**
  - **`WhisperCppEngine` (`whisper.xcframework` Metal GPU + `flash_attn` + `Beam Search 5`):** Full 32-layer **`Large-v3` (FP16)** and **`Large-v3 (Q5_0)`** models delivering state-of-the-art multilingual fluency and technical terminology recall across German, Turkish, and English.
  - **`Qwen3ASREngine` (Pure C `CQwenASR` + Apple `Accelerate` BLAS / NEON):** Native C execution of **`Qwen3-ASR-1.7B`** with zero Python or PyTorch runtime dependencies — delivering zero repetition loops and verbatim developer syntax for file paths (`examples/source/.../machine_data_library.py`) and hardware symbols (`C++`, `Sink Modul`).
- **🛡️ Neural Silero VAD v6.2.0 + Pure Swift `vDSP` Acoustic Pre-Conditioning:**
  - **95 Hz Butterworth High-Pass Filter & Quiet-Speech Gain (`AudioConditioner`):** Strips sub-100 Hz desk thumps, microphone handling rumble, and HVAC hum; applies a soft-knee limited (`tanh`) linear boost up to `+12 dB` **only** to genuinely quiet recordings (`p90 < -32 dBFS`) that exhibit real speech modulation dynamics (`p90 > p15 * 1.8`).
  - **Neural Voice Activity Detection (`SileroVAD v6.2.0`):** Uses the embedded `864 KB` Silero LSTM model via `whisper.xcframework`'s C API to achieve **`0/5 (0 words)`** false positives across silence traps while slicing speech into independent `<= 28.0s` windows.
- **🧹 3-Tier Surgical Post-Processing (`TranscriptPostProcessor`):**
  - Eliminates silence and subtitle-credit hallucinations (`"es heilt die göttliche Kraft"`, `"amara.org"`, `"Teksting av Nicolai Winther"`, `"Hvað er það?"`), standalone outro boilerplate (`"Vielen Dank"`, `"Amen"`, `"Thank you for watching"`), and intra-/inter-segment repetition loops without clipping legitimate technical sentences.
- **🚫 Zero External Setup:** No Python, PyTorch, MLX, Homebrew, or Terminal setup required. Download a single `.dmg` and run.
- **👁️ Real-Time Live Streaming & Word-Level Audio Sync:** Decoded segments stream live to the UI; click any word to seek the audio player directly to that timestamp (`±100 ms`).
- **📁 Watched Folders, Apple Voice Memos & iCloud Drive Sync:** Automatically detects new recordings in watched folders or Apple Voice Memos, triggers background downloads for dateless `.icloud` placeholders, and avoids duplicate work via `TranscriptCacheManager`.

---

## 🧠 AI Agent & Engineering Reference: Pipeline Architecture & Empirical Parameter Rationale

> **Purpose of This Section:** This specification is written for AI coding agents (LLMs) and engineers inspecting or proposing optimizations to Transkript Hub. It documents **why specific models were retained or pruned, how the 5-stage audio/transcription pipeline operates, and the exact empirical benchmark evidence behind every parameter value**. Before modifying any threshold, flag, or model entry, read the empirical findings and **"Hard Invariants for Future AI Agents"** below.

---

### 1. Model Curation & Pruning Decisions (Why Only 3 Models Remain)

Core design principle: **"Speed is secondary; the sole primary objective is maximum transcription accuracy, zero hallucination, and technical/multilingual (German + Turkish + English) fidelity."**

All decisions are grounded in a **132-run sequential benchmark** (`11` model configurations × `12` real-world clips: `5` dense 150s German CAD/Python/SystemC engineering and Turkish conversation clips = `750s`, `2` additional Turkish/sparse German clips = `910.23s` total speech, plus `5` real silence/ambient noise traps) and **3 controlled A/B experiments** executed on an **Apple M1 Pro** (10 CPU cores, 16 GB unified memory).

#### ✅ The 3 Curated High-Accuracy Models (`>= 1 GB` and `>= 9.5/10` Accuracy)

| Model (`WhisperModelCatalog`) | Size | Engine & Hardware Backend | In-App Score (`Speed` / `Accuracy`) | Measured M1 Pro Throughput | Why It Is Retained (Specialized Role) |
| :--- | :---: | :--- | :---: | :---: | :--- |
| **`Large-v3`** (`ggml-large-v3.bin`) | **3.09 GB** | `WhisperCppEngine` (`whisper.xcframework` Metal GPU FP16 + `flash_attn`) | **6.8/10** Speed<br>**9.7/10** Accuracy | `11.94x` raw / **`19.7x–21.6x`** (with Silero VAD) | **#1 Overall Multilingual & Technical Accuracy Champion (Default Model).** Full 32 decoder layers (FP16). Achieved **7/7** on German CAD/motor engineering terms (`Notch, Kerbe, Luftpolster, Metall, Open Folder, Mindstorms, Klasse`), **7/8** on Python architecture terms, and the highest morphological fidelity on conversational Turkish. |
| **`Qwen3-ASR-1.7B`** (`qwen3-asr-1.7b/`) | **4.70 GB** | `Qwen3ASREngine` (Pure C `CQwenASR`, Apple `Accelerate` BLAS + NEON CPU, `-O3 -ffast-math`) | **5.0/10** Speed<br>**9.6/10** Accuracy | `6.16x` dense / **`8.70x`** average (CPU) | **#1 Zero-Loop & Code / File-Path Specialist.** Recorded **0 repetition loops (`loops=0`)** and **0 Whisper boilerplate hallucinations** across all 132 runs. Formats spoken Python file paths directly in developer syntax (`examples/source/machineauslagerung/design/libraries/machine_data_library.py`) and distinguishes hardware terms (`Source Modul und ein Sink Modul`, `C++`) where Whisper models write `"Sync-Modul"`. |
| **`Large-v3 (Q5_0)`** (`ggml-large-v3-q5_0.bin`) | **1.08 GB** | `WhisperCppEngine` (`whisper.xcframework` Metal GPU Q5_0 + `flash_attn`) | **6.0/10** Speed<br>**9.5/10** Accuracy | `9.54x` raw (Metal Q5_0) | **#1 Compact 32-Layer Model.** Preserves the full **32-layer** decoder depth in `1.08 GB` for memory-constrained workloads without dropping to a 4-layer distilled decoder; matched FP16 with **7/7** CAD term recall and only `1` loop across 12 clips. |

#### ❌ Pruned Models & Empirical Elimination Rationale

1. **`Tiny` (75 MB, `4.0/10`), `Base` (142 MB, `5.5/10`), `Small` (466 MB, `7.2/10`):** All sub-1 GB models suffer severe word error rates and morphological degradation on technical German and conversational Turkish. Removed to prevent accidental low-quality transcriptions.
2. **`Large-v3-Turbo (Q5_0)` (547 MB, `8.5/10`):** Under the 1 GB threshold; furthermore, on Apple Silicon Metal GPU, Q5_0 dequantization overhead makes it both slower (`21.43x` vs `24.48x`) and less accurate than FP16 `Turbo`.
3. **`Medium` (1.5 GB, `8.2/10`):** **Strictly Pareto-dominated.** It is both **larger** than `Large-v3 (Q5_0)` (`1.5 GB` vs `1.08 GB`) and **significantly less accurate** (`8.2/10` vs `9.5/10`).
4. **`Large-v3-Turbo` (1.6 GB FP16, `8.8/10`):** Distills `Large-v3`'s 32 decoder layers down to **4 decoder layers solely for speed**. Our empirical benchmark proved that this 32→4 layer reduction introduces phonetic substitutions in technical German (`"spätestens die Größe"` → `"spätestens die Pulse"`, `"irgendwas Speciales"` → `"irgendwie Schlimmes"`) and Turkish (`"Brem şeyi"` → `"Brams şeyi"`, `"dinleyelim"` → `"zümleyelim"`). Because `Silero VAD v6.2.0` already accelerates full 32-layer `Large-v3` to **`~20x` real-time** (transcribing a 94-minute recording in ~4.5 minutes), keeping a lower-accuracy 4-layer model is unjustified when accuracy is the priority.
5. **`Qwen3-ASR-0.6B` (1.88 GB, `8.4/10`):** Larger than `Large-v3 (Q5_0)` (`1.08 GB`, `9.5/10`) yet lower in accuracy (`8.4/10`), exhibited a repetition loop (`"Du klickst, klickst, klickst"`) on `rec7_s3_cad_tech`, and showed character drift (`"sohren"`, `"ilpaşım"`) on short Turkish clips. Superfluous alongside `Qwen3-ASR-1.7B` (`9.6/10`, `0` loops).
6. **`NVIDIA Parakeet TDT 0.6B v3 (MLX)` *(Evaluated, not integrated)*:** Despite blistering German speed (`36.23x`) and `0/5` silence false positives, it has **zero Turkish support** (produced **0 words** on both `short_freunder` and `rec3_s1`), corrupted `C++` into **`C<unk>`**, and requires an external Python/MLX runtime.

---

### 2. End-to-End 5-Stage Audio & Transcription Pipeline

Every audio input passes through the following deterministic 5-stage pipeline for both **`WhisperCppEngine`** and **`Qwen3ASREngine`**:

```text
[ Audio / Video File (.m4a, .mp3, .wav, .ogg, .opus, .mp4, .mkv ...) ]
                                  │
                                  ▼
   STAGE 1: AudioDecoder (16 kHz Mono Float32 PCM, AVAudioQuality.max + FFmpeg Fallback)
                                  │
                                  ▼
   STAGE 2: AudioConditioner (Pure Swift Accelerate / vDSP)
            ├─ 2.1 DC Offset Removal (vDSP_meanv + vDSP_vsadd)
            ├─ 2.2 95 Hz 2nd-Order Butterworth High-Pass Filter (Q = 0.7071)
            └─ 2.3 Speech-Modulation-Gated Conditional Linear Quiet-Speech Gain
                   (Only when 0.002 < p90 < 0.025 and p90 > max(p15 * 1.8, 0.003): <= 4.0x + tanh 0.95)
                                  │
                                  ▼
   STAGE 3: Dual-Layer VAD & Mandatory <= 28.0s Independent Slicing
            ├─ 3.1 Fast Energy Pre-Gate: AudioVAD.detectSpeech (instant exit if maxFrameRMS < 0.012)
            ├─ 3.2 Primary Neural VAD: SileroVAD v6.2.0 (whisper_vad_segments_from_samples,
            │      threshold=0.35, minSpeech=200ms, minSilence=500ms, maxSpeech=28s, pad=250ms, bridge=0.8s)
            └─ 3.3 Offline Fallback & Hard Cap: Qwen3ASREngine.splitSpeechSegments(maxDuration: 28.0s)
                                  │
                    ┌─────────────┴─────────────┐
                    ▼                           ▼
   STAGE 4A: WhisperCppEngine          STAGE 4B: Qwen3ASREngine
   (Large-v3 FP16 / Large-v3 Q5_0)     (Qwen3-ASR-1.7B Pure C CQwenASR)
   • use_gpu = true (Metal)            • Accelerate BLAS + NEON (-O3 -ffast-math)
   • flash_attn = true                 • segment_sec = 0.0, skip_silence = 0
   • BEAM_SEARCH (beam_size = 5)       • past_text_conditioning = 0 (noContext=true)
   • no_context = true (-mc 0)         • qwen_set_threads(threads)
   • suppress_nst = true (-sns)        • qwen_set_force_language("German"/"Turkish"/...)
   • no_speech_thold = 0.60            • qwen_set_prompt(initialPrompt)
   • entropy_thold = 2.40              • Segment.interpolateWords(...)
   • temperature = 0.0, inc = 0.20
                    └─────────────┬─────────────┘
                                  ▼
   STAGE 5: TranscriptPostProcessor & SRTFormatter
            ├─ Tier A: Pure Hallucination & Dynamic Broadcaster Credit Stripping (German verb/tech-stem protected)
            ├─ Tier B: Standalone Outro/Boilerplate Pruning ("Vielen Dank", "Amen", "Thank you" ...)
            ├─ Tier C: Intra-/Inter-Segment N-Gram, Ping-Pong & Single-Word Loop Deduplication
            └─ SRTFormatter: <= 42 chars/line, <= 2 lines/cue SubRip (.srt) subtitle export
```

---

### 3. Per-Stage Parameter Specifications & Empirical Justification ("Why This Exact Value?")

#### Stage 1 — `AudioDecoder.swift` (`Sources/TranskriptHubCore/Audio/AudioDecoder.swift`)
- **`targetSampleRate = 16000.0` (Mono `Float32`):** Required natively by Whisper's Log-Mel feature extractor, `CQwenASR`, and `SileroVAD v6.2.0`.
- **`converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue`:** Prevents high-frequency sibilant aliasing (`s, sch, f, t, k, ç, ş`) when downsampling from `48 kHz` / `44.1 kHz` to `16 kHz`.
- **`decodeViaFFmpeg(fileURL:)` Fallback:** Automatically transcodes `.ogg`, `.opus` (WhatsApp voice notes), `.wma`, and `.webm` containers not natively opened by `AVAudioFile` into `16 kHz` mono PCM.

#### Stage 2 — `AudioConditioner.swift` (`Sources/TranskriptHubCore/Audio/AudioConditioner.swift`)
- **Step 2.1 — DC Offset Removal (`vDSP_meanv` + `vDSP_vsadd`):** Eliminates constant DC bias from microphone ADCs before IIR filtering and RMS energy computation.
- **Step 2.2 — `highPassCutoffHz = 95.0` (2nd-Order Butterworth HPF, `Q = 0.70710678`):**
  - *Why `95 Hz`?* Human speech fundamental frequencies (F0) and first formants lie at `>= 100 Hz`, whereas desk thumps, microphone handling bumps, HVAC hum, and car-engine sub-harmonics concentrate at `10–90 Hz`.
  - *Empirical Proof:* Sub-100 Hz desk taps (`-38 dB`) in `short_rec4_silence`, `short_rec5`, `short_rec6`, and `rec_main_s1` triggered Whisper hallucinations (`"*tap* *tap*"`, `"Hvað er það?"`, `"Norske Skogsforskning"`). Filtering below `95 Hz` removed the impulse triggers without affecting vocal formants.
- **Step 2.3 — Speech-Modulation-Gated Conditional Linear Quiet-Speech Gain:**
  - *Trigger Condition:* Across sorted 20 ms frame RMS values, `0.002 < p90 < 0.025` (`-54 dBFS .. -32 dBFS`) **AND** `p90 > max(p15 * 1.8, 0.003)`.
  - *Gain Law:* `gain = min(4.0, 0.050 / p90)` (up to `+12 dB`), with a smooth soft-knee `tanh(scaled) * 0.95` limiter above `|scaled| > 0.85`.
  - **⚠️ CRITICAL AI AGENT WARNING — Why Unconditional `FFmpeg loudnorm` / `dynaudnorm` / `RNNoise` Must NOT Be Used:**
    1. In our controlled A/B experiment (`task-2598`), applying the commonly recommended `highpass=f=100,loudnorm=I=-16:TP=-1.5:LRA=11` chain to an already-loud outdoor Turkish recording (`rec3_s1`, mean `-25.3 dB`, `6.1% <-45 dB`) crushed dynamic range, pumped background engine noise, and caused `Whisper Large-v3` word recovery to collapse from **`117` words down to `65` words** (while hallucinating `"İzlediğiniz için teşekkür ederim."`).
    2. By gating linear gain strictly on `p90 < 0.025` AND speech modulation `p90 > p15 * 1.8`:
       - Loud/normal clips `rec3_s1` (`p90 = 0.0839` → `gain = 1.00x`) and `short_freunder` (`p90 = 0.0381` → `gain = 1.00x`) retain untouched micro-dynamics (`short_freunder` improved from `19 → 26` words, recovering the soft opening word `"iyiydim."`; `rec3_s1` preserved `113` words).
       - Stationary fan hum in `rec_main_s1` (`p90 / p15 < 1.8`) is never amplified.
       - Genuinely quiet office/engineering speech in `rec7_s3_cad_tech` (`-43.2 dB`, `p90 = 0.0105` → `gain = 4.00x`) and `rec2_s1` (`p90 = 0.0102` → `gain = 4.00x`) receives a clean `+12 dB` linear lift, increasing `Large-v3` word recall from `123 → 152` words and `Qwen3-ASR-1.7B` from `163 → 184` words (fixing Qwen's `"Notsche"` to `"Notch"`).

#### Stage 3 — Dual-Layer VAD (`SileroVAD.swift` + `AudioVAD.swift`) & Mandatory `<= 28.0s` Independent Slicing
- **Primary Neural Detector (`SileroVAD.swift` — `ggml-silero-v6.2.0.bin`, `864 KB`):**
  - Invokes `whisper.xcframework` (`v1.9.2`) C API (`whisper_vad_init_from_file_with_params` + `whisper_vad_segments_from_samples`) on CPU BLAS (`cparams.use_gpu = false`, `n_threads = 4`, `~170x–260x` real-time).
  - **Parameters & Empirical Justification:**
    - `threshold = 0.35`: The default `0.50` threshold clipped the soft Turkish opening word `"iyiydim"` (`0.00–1.21s`) in `short_freunder.wav` (starting at `1.60s`). Lowering `threshold` to `0.35` paired with `AudioConditioner` captured `0.00–1.21s` completely **AND** reduced silence-trap false positives (`sil5`) from **`5/5 (32–50 words) → 0/5 (0 words)`**.
    - `minSpeechDurationMs = 200`: Rejects sub-200 ms transient clicks.
    - `minSilenceDurationMs = 500`: Prevents premature splitting across natural breathing pauses.
    - `maxSpeechDurationSeconds = 28.0`: Stays safely below Whisper's 30.0s positional embedding boundary and Qwen3-ASR's chunk stability window.
    - `speechPadMs = 250` and `bridgeGapSeconds = 0.80` (bridged only when the combined segment remains `<= 28.0s`).
  - **⚠️ CRITICAL AI AGENT WARNING 1 — `whisper_vad_segments_get_segment_t0/t1` Timestamp Units:** In `whisper.cpp 1.9.2`, these functions return **centiseconds (`100.0 == 1.0 second`)**, NOT seconds or milliseconds (`Double(t0) / 100.0`). Dividing by `1.0` or `1000.0` breaks all segment timestamps.
  - **⚠️ CRITICAL AI AGENT WARNING 2 — Why We Do NOT Enable `wparams.vad = true` Internal Stitching:**
    - When `wparams.vad = true` is enabled inside `whisper.cpp`, the C runtime concatenates all VAD intervals into a single stitched buffer before calling `whisper_full()`.
    - In our diagnostic (`task-2598` / `rec3_s1`), `Large-v3` (`beam=5`) hit a stitched boundary jump (`00:00:39.100 --> 00:01:09.310`, `30.21s` span) in noisy Turkish speech, triggered internal `no_speech` skipping, and dropped the remaining windows (`117` words collapsed to `28–44` words).
    - Instead, we extract `[SpeechSegment]` via `SileroVAD.detectSpeech` and invoke `whisper_full()` / `qwen_transcribe_audio()` **independently per real contiguous audio slice** with its exact `offsetSeconds`. This makes stitched-boundary drops and timestamp drift impossible.
- **Fast Energy Pre-Gate & Offline Fallback (`AudioVAD.swift`):**
  - Computes 20 ms `vDSP_rmsqv` frame energies (`minSpeechRMS = 0.012`) and estimates the noise floor exclusively from sub-speech frames (`< 0.012`, `maxAdaptiveThresholdRMS = 0.014`). Short-circuits pure silence in `< 1 ms` before allocating neural VAD buffers and serves as an automatic offline fallback if `ggml-silero-v6.2.0.bin` is absent.

#### Stage 4A — `WhisperCppEngine.swift` (`Large-v3` & `Large-v3 (Q5_0)`) Parameters
- **`cparams.use_gpu = true` & `cparams.flash_attn = true`:** Enables Flash Attention on the Apple Silicon Metal GPU, eliminating quadratic memory bandwidth bottlenecks with zero WER loss. (Preferred over CoreML `.mlmodelc`, which forces rigid 30-second zero-padding on variable-length `1..28s` VAD slices.)
- **`strategy = WHISPER_SAMPLING_BEAM_SEARCH` (`beamSize = 5`):**
  - *Empirical Proof:* Greedy decoding (`beamSize = 1`) dropped the soft opening word `"iyiydim"` and misheard `"ilk başım"` as `"ilk başın"` in `short_freunder.wav`, whereas `beamSize = 5` (`task-2598` & `task-2784`) recovered both words and captured **7/8** Python architecture terms in `rec7_s4_python_pause`. With `SileroVAD` stripping silence, `Large-v3` with `beamSize = 5` still runs at **`~20x` real-time**.
- **`wparams.no_context = options.noContext` (Default: `true`, CLI: `-mc 0`):**
  - *Empirical Proof:* With `no_context = false`, 32-layer `Large-v3` conditioned each 28s window on the previous window's text, suffering **13 repetition loops** and scoring only **3/7** on CAD technical terms (`rec7_s3_cad_tech`). Setting `no_context = true` eliminated the loops and raised CAD term recall from **3/7 → 7/7**.
  - *(Note: `AppViewModel.swift` lines 2325 and 2519 previously hardcoded `noContext: false`, ignoring the user's Anti-Hallucination toggle; this bug was fixed by binding `noContext: antiHallucination`.)*
- **`wparams.suppress_nst = true` (`-sns`) & `wparams.suppress_blank = true`:** Suppresses non-speech tokens (`♪`, `* musik *`, `[Applaus]`) that otherwise act as launchpads for hallucinations.
- **`wparams.no_speech_thold = 0.60`, `wparams.entropy_thold = 2.40`, `wparams.temperature = 0.0`, `wparams.temperature_inc = 0.20`:** Starts deterministically at `0.0` temperature and increments by `0.20` only when token Shannon entropy falls below `2.40` (indicating a repetition loop).
- **`wparams.carry_initial_prompt = (normalizedPrompt != nil)`:** When a domain glossary `--prompt` is supplied (`"SPSM, DXF, Geo, Mesh, PyWrapper..."`), carries only that clean glossary across every 28s slice even when `no_context = true`.

#### Stage 4B — `Qwen3ASREngine.swift` (`Qwen3-ASR-1.7B` Pure C `CQwenASR`) Parameters
- **Compiler Flags (`Package.swift` — `Sources/CQwenASR`):**
  - `-DUSE_BLAS -DACCELERATE_NEW_LAPACK -O3 -ffast-math` + `-framework Accelerate`.
  - *Empirical Proof:* Without `-O3 -ffast-math`, SwiftPM Debug builds took `41.00s` on `short_freunder.wav` (`10.23s`); adding `-O3 -ffast-math` reduced execution time to **`4.19s` (a 10x speedup)**.
- **Mandatory `<= 28.0s` VAD Chunking (`Qwen3ASREngine.maxChunkSeconds = 28.0`):**
  - **⚠️ CRITICAL AI AGENT WARNING:** In our benchmark, feeding un-sliced 150s sparse audio (`rec2_s1`) to `Qwen3-ASR-1.7B` (`mlx-audio` 8-bit) without `<= 28s` VAD segmentation caused a catastrophic **2,731-word `"Hallo. Hallo. ..."` infinite decoder loop (`184.27s = 0.81x` RTF)**. Feeding the exact same clip via `<= 28s` VAD slices to pure C `Qwen3ASREngine` completed in **`5.49s` (`27.35x` RTF) with `22` words and `0` loops**. Therefore, `ctx.pointee.segment_sec = 0.0` and `ctx.pointee.skip_silence = 0` are set on the C struct so Swift's `AudioConditioner + SileroVAD + splitSpeechSegments(maxDuration: 28.0)` retains 100% control over slice boundaries and timestamp interpolation.
- **`ctx.pointee.past_text_conditioning = options.noContext ? 0 : 1`:** Defaults to `0` (`noContext = true`) to prevent cross-slice error propagation.
- **`Qwen3ASREngine.mapLanguageCode(_:)`:** Maps ISO-639-1 codes (`"de"`, `"tr"`, `"en"`, ...) to Qwen3-ASR canonical English language names (`"German"`, `"Turkish"`, `"English"`, ...); passes `nil` for `"auto"` so Qwen uses native language identification.

#### Stage 5 — `TranscriptPostProcessor.swift` & `SRTFormatter.swift`
- **3-Tier Surgical Post-Processing (`TranscriptPostProcessor.swift`):**
  1. **Tier A (`pureHallucinationPhrases` & Dynamic Credit/Copyright Regexes):** Strips `"es heilt die göttliche kraft"`, `"amara.org"`, `"altyazı m k"`, and the Nordic silence hallucinations observed in our desktop tests (`"teksting av nicolai winther"`, `"hvað er það"`, `"það er það er það"`, `"norske skogsforskning"`) at both segment and sentence levels. Dynamic broadcaster (`ZDF`, `ARD`, `ORF`, `Subtitles by...`) regexes include German verb and engineering-stem guards (`creditSentenceVerbRegex`, `creditTechStemRegex`) so legitimate technical sentences are never misclassified as credits.
  2. **Tier B (`standaloneBoilerplatePhrases`):** Prunes `"vielen dank"`, `"amen"`, `"thank you for watching"`, `"izlediğiniz için teşekkürler"`, etc. **strictly when the entire normalized segment equals the boilerplate phrase** — never stripping them from real conversational sentences.
  3. **Tier C (Repetition & Single-Word Collapse Deduplication):** Collapses consecutive n-gram repetitions (`3+` repeats → `1`), inter-segment A-B-A-B ping-pong loops, and single-word stutter tails (`"Ich habe, das ist, das ist, das ist..."`).
- **`SRTFormatter.swift`:** Formats word-level timestamps into SubRip (`.srt`) cues respecting `<= 42` characters per line and `<= 2` lines per cue without splitting words, supporting `>= 100`-hour rollovers.

---

### 4. Hard Invariants for Future AI Agents (Do Not Break)

1. **Never add `< 1 GB` models or models with `< 9.5/10` empirical accuracy back into `WhisperModelCatalog.availableModels`** (and always keep `availableModels` sorted strictly ascending by `sizeBytes` with `summary.count <= 40` — enforced by `FolderWatcherTests`).
2. **Never use unconditional `loudnorm` or a `p50` noise-floor reference in `AudioConditioner`:** In recordings where the speaker talks `> 50%` of the time, `p50` falls inside active speech. Always use **`p15`** (`p90 > max(p15 * 1.8, 0.003)`).
3. **Never enable `wparams.vad = true` inside `WhisperCppEngine`:** Always extract speech segments in Swift via `SileroVAD.detectSpeech` (+ `AudioVAD.detectSpeech` fallback) and pass independent `<= 28.0s` slices to `whisper_full()`.
4. **Always divide `whisper_vad_segments_get_segment_t0/t1` by `100.0` in `SileroVAD.swift`** (`centiseconds -> seconds`).
5. **Never remove the `maxChunkSeconds <= 28.0` bound in `Qwen3ASREngine`** or the `-O3 -ffast-math` C flags on `CQwenASR` in `Package.swift`.
6. **Never hardcode `noContext: false` in `AppViewModel.swift`** (it must remain bound to `noContext: antiHallucination`) and never remove the completed-item subtitle sanitization (`"Ses Transkript Ediliyor..."` → `"Ses Transkripti • Tamamlandı"`) in `updateItem` and the queue views.
7. **Always run `swift test` (`303/303` tests passing) and `gitleaks git .` (`0` leaks) before considering any change complete.**

---

## 🏗️ Project Structure

```text
TranskriptHub
├── Sources/
│   ├── CQwenASR/                  # Pure C Qwen3-ASR core (Apple Accelerate BLAS + NEON, -O3 -ffast-math)
│   ├── TranskriptHubCore/         # Pure Swift Core Library
│   │   ├── Audio/                 # AudioDecoder, AudioConditioner (vDSP), SileroVAD v6.2.0, AudioVAD, AudioValidator
│   │   ├── Transcription/         # WhisperCppEngine, Qwen3ASREngine, TranscriptionEngineFactory, TranscriptPostProcessor, WhisperModelCatalog
│   │   ├── Output/                # OutputWriter (atomic .txt), SRTFormatter (<=42 chars SubRip .srt)
│   │   ├── Cache/                 # TranscriptCacheManager (title + duration + externalID smart deduplication)
│   │   ├── Database/              # GRDB.swift SQLite persistent state machine
│   │   └── System/                # ClipboardMonitor, FolderWatcher (iCloud & Voice Memos)
│   ├── TranskriptHubApp/          # SwiftUI 6 macOS Studio UI (UnifiedStudioHubView, MenuBarMiniWindow)
│   └── transkripthub-cli/         # Native CLI (--model, --lang, --no-context, --prompt, --srt)
├── Frameworks/
│   └── whisper.xcframework/       # Metal GPU + Flash Attention + Silero VAD C API whisper.cpp (v1.9.2)
└── Tests/
    └── TranskriptHubCoreTests/    # 303 unit, stress, and 4-tier E2E verification tests
```

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| <kbd>⌘</kbd> + <kbd>Return</kbd> | Start Queue Transcription |
| <kbd>⌘</kbd> + <kbd>V</kbd> | Paste Link from Clipboard |
| <kbd>⌘</kbd> + <kbd>O</kbd> | Open Audio / Video File Picker |
| <kbd>⇧</kbd> + <kbd>⌘</kbd> + <kbd>T</kbd> | Open Transcript Folder in Finder |
| <kbd>⌘</kbd> + <kbd>K</kbd> | Open Command Palette |
| <kbd>⌘</kbd> + <kbd>,</kbd> | Open Settings |
| <kbd>⌘</kbd> + <kbd>1</kbd> / <kbd>2</kbd> / <kbd>3</kbd> | Switch between Queue / History / Watched Folders |
| <kbd>⇧</kbd> + <kbd>⌘</kbd> + <kbd>B</kbd> | Toggle Clipboard Monitoring |

---

## 🚀 Getting Started & Building from Source

### 1-Click macOS Installation
1. Click the **Download Transkript Hub** badge at the top (or visit [GitHub Releases](../../releases)) to download **`TranskriptHub.dmg`**.
2. Open the DMG and drag **Transkript Hub** into your **Applications** folder.
3. Launch the app, ensure **`Large-v3` (3.09 GB)**, **`Qwen3-ASR-1.7B` (4.70 GB)**, or **`Large-v3 (Q5_0)` (1.08 GB)** is downloaded in the model picker, and drop your audio or video files.

### Building from Source & CLI Usage

```bash
# 1. Run the full unit, stress, and E2E test suite (303 tests)
swift test

# 2. Build release binaries and package the signed DMG / .app bundle
./scripts/package_dmg.sh

# 3. Transcribe via CLI using Large-v3 + Silero VAD + AudioConditioner + SRT export
.build/release/transkripthub-cli transcribe "recording.m4a" \
  --model large-v3 \
  --lang de \
  --no-context \
  --srt \
  --prompt "SPSM, DXF, Geo, Mesh, PyWrapper, Paraview, Assembly, MachineDataLibrary"

# 4. Transcribe via CLI using Qwen3-ASR-1.7B (Pure C Apple Accelerate)
.build/release/transkripthub-cli transcribe "recording.m4a" \
  --model qwen3-asr-1.7b \
  --lang de \
  --no-context \
  --srt
```

---

## 📄 License

This project is licensed under the [MIT License](LICENSE). Third-party components (`whisper.cpp`, `antirez/qwen-asr`, `Silero VAD`, `GRDB.swift`, `yt-dlp`, `Deno`) remain subject to their respective open-source licenses.
