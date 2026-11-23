# Transkript Hub — Agent Instructions

> Single source of truth shared across **Claude**, **Gemini / Antigravity**, and **ChatGPT / Codex** (`CLAUDE.md` is symlinked to this file).

## 1. Project Overview & Product Invariants
- **App:** Native macOS 14+ (Sonoma/Sequoia) local AI transcription studio & CLI (`TranskriptHubApp`, `TranskriptHubCore`, `transkripthub-cli`).
- **Zero-Cloud Privacy (Non-Negotiable):** Every byte of audio, video, and transcript stays 100% local on the user's Mac. Never introduce cloud transcription uploads or telemetry.
- **Tech Stack:**
  - **Swift 6.0** with `StrictConcurrency` enabled (`Package.swift`).
  - **Local Engines:** Bundled `Frameworks/whisper.xcframework` (Metal GPU / Accelerate + built-in Silero VAD) and `Sources/CQwenASR` (C + Apple Accelerate/BLAS/LAPACK). **Do not** depend on Homebrew `whisper.cpp`.
  - **Persistence:** `GRDB.swift` (`>= 7.0.0`, SQLite cache & deduplication).
  - **External CLI Tools:** `/opt/homebrew/bin/ffmpeg`, `/opt/homebrew/bin/ffprobe`, `yt-dlp`.
  - **UI & Design:** Native SwiftUI + AppKit (`NSVisualEffectView` Liquid Glass translucency, Muted Luxury palette — see `PRODUCT.md` and `design.md`).
  - **Localization:** Maintain all 5 interface languages (Turkish, English, German, French, Spanish) in `AppLanguage.swift` when adding/changing UI copy.
  - **Accessibility & Keyboard:** Preserve `@Environment(\.accessibilityReduceMotion)`, VoiceOver `.accessibilityLabel`s, and keyboard shortcuts (`⌘V`, `⌘O`, `⌘R`, `⌘⇧C`, `⌘A`, `Space`, `⌘←`, `⌘→`, `⌘Return`).

## 2. Repository Structure
- `Sources/TranskriptHubCore/` — Transcription engines, model catalog, audio extraction/VAD, SQLite cache, YouTube ingestion.
- `Sources/TranskriptHubApp/` — SwiftUI/AppKit studio UI, karaoke waveform canvas, localization.
- `Sources/CQwenASR/` — C/Accelerate ASR backend (`include/`).
- `Sources/transkripthub-cli/` — Command-line interface.
- `Tests/TranskriptHubCoreTests/` & `Tests/Fixtures/` — Automated test suite.
- `scripts/package_dmg.sh`, `scripts/release.sh` — Packaging `.app` / `.dmg` (copies bundled `whisper.xcframework`).

## 3. Deterministic Quality Gates
Before claiming any change is complete, run and report exact exit codes:
```bash
# Build & test
swift build
swift test

# Format & lint (on touched Swift files or repo)
swiftformat --lint Sources/TranskriptHubCore Sources/TranskriptHubApp Sources/transkripthub-cli Tests
swiftlint lint --quiet
```
- Never weaken `StrictConcurrency` or suppress warnings/tests just to pass.
- Do not modify `Frameworks/whisper.xcframework` or release artifacts (`dist/`) unless explicitly requested.

## 4. Multi-Agent Relay Protocol (Claude ↔ Gemini/Antigravity ↔ ChatGPT/Codex)
- **On start:** Read `.ai/HANDOFF.md` and run `git status -s` / `git diff --stat`.
- **Before switching AI apps:** Update `.ai/HANDOFF.md` using the shared `handoff` skill (goal, changed files, verified `swift build`/`swift test`/`swiftlint`/`swiftformat` results, open risks, exact next step). `.ai/` is excluded locally via `.git/info/exclude` — never commit `.ai/`.
- **Cross-model review:** Inspect `git diff` directly, check Swift 6 concurrency safety, 5-language localization parity, and re-run `swift test` + `swiftlint`.
- **Docs lookup:** Use `context7` MCP when checking Swift 6 concurrency, `GRDB.swift` 7, `ScreenCaptureKit`, or `AVAudioEngine` APIs.
