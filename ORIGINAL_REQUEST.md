# Original User Request

## Initial Request — 2026-10-15T16:34:34Z

Transform Transkript Hub into an AAA Apple 1st-Party quality, privacy-first, ultra-optimized macOS transcription powerhouse that rivals and surpasses MacWhisper Pro and Superwhisper in speed, elegance, and Apple ecosystem integration, while maintaining a lean binary size (<10MB DMG) and zero unnecessary third-party package dependencies.

Working directory: /Users/akifulutas/Documents/Akif/Transkript Hub.txt
Integrity mode: development

## Requirements

### R1. Native Interactive Audio Waveform & Karaoke-Style Synchronized Player
- Integrate native AVFoundation audio playback synchronized with word-level and segment-level timestamps.
- Render a responsive, Apple Voice Memos-style interactive waveform visualizer with click-to-seek and scrub capabilities.
- Implement karaoke-style active word highlighting: as audio plays, the spoken word illuminates smoothly, and clicking any word in the transcript jumps audio playback directly to that millisecond timestamp.

### R2. In-App Audio & Microphone Recording Engine
- Add a direct audio recording engine powered by AVAudioEngine / AVAudioRecorder.
- Provide an animated live audio meter / frequency bar visualizer during recording.
- Support instant, one-click transcription the moment recording stops, with auto-save to user's history and export directory.

### R3. Speaker Diarization & Inline Rich Transcript Editor
- Categorize transcript segments by speaker turns with distinct Apple-style colored badges (e.g., Speaker 1, Speaker 2) with editable custom names.
- Enable inline editing of transcripts directly inside the native view, allowing users to correct terms without exporting.
- Provide local summary, bullet-point action items, and timestamped chaptering.

### R4. Menu Bar Companion & Floating Drop-Zone Widget
- Provide a lightweight Menu Bar extra (NSStatusItem) allowing users to drag-and-drop audio files or paste YouTube URLs without opening the main window.
- Include a global hotkey or quick-record toggle for instantaneous dictation/recording.

### R5. Deep macOS Sequoia Ecosystem Integration & Apple HIG Elegance
- Implement Apple's modern "Liquid Glass" design language with NSVisualEffectView vibrancy, SF Symbols 6, unified macOS window toolbar, and split view navigation.
- Implement native keyboard shortcuts: ⌘K for Command Palette, Space for play/pause, ⌘F for interactive search with hit navigation, and ⌘E for instant multi-format export.
- Support Quick Look previews and deep system integration with Apple Voice Memos and iCloud Drive.

### R6. Extreme Performance & Zero-Dependency Architectural Mandate
- Keep the application footprint ultra-lean (<10 MB DMG distribution).
- Strictly adhere to Swift 6 Concurrency, zero-copy memory transfers, and Accelerate/vDSP optimizations.
- Zero extraneous third-party dependencies; rely strictly on Apple native frameworks (AVFoundation, AppKit, SwiftUI, Accelerate, CryptoKit, OSLog).

## Acceptance Criteria
- [ ] Clicking any word in the transcript jumps audio playback to the exact timestamp (±100ms accuracy).
- [ ] Waveform scrubs smoothly at 60/120 fps during playback without UI hitching or main thread drops.
- [ ] Spacebar toggles playback; playback controls reflect exact current position and total duration.
- [ ] Direct recording starts and stops cleanly via microphone; audio files are saved in uncompressed/AAC format.
- [ ] Live audio waveform/meter reacts in real time to input volume.
- [ ] Speaker badges are clearly distinguished and allow inline renaming.
- [ ] Editing transcript text updates the underlying database model atomically.
- [ ] Packaged DMG binary size remains strictly under 15 MB.
- [ ] App launches in under 200 ms on Apple Silicon.
- [ ] All 39 existing unit and integration tests continue to pass without regressions (swift test).
- [ ] swift build compiles cleanly with zero warnings or errors.


## Follow-up — 2026-10-15T17:11:39Z

User Design Direction Update:
The user has provided an exact visual design reference (warm frosted glassmorphism / visionOS / macOS Sequoia liquid glass).
Key UI deliverables:
1. 4-column KPI metric summary cards at the top of the main dashboard.
2. Frosted glass cards with top-left status indicator badges (green • Ready, blue • In Progress, purple • Watched, red • Error).
3. Circular/donut distribution breakdown card (audio sources & formats).
4. Recent activity card table with speaker avatars and duration.
5. Liquid glass sidebar with grouped sections and bottom system status capsule.
Ensure that Milestone 1 and Milestone 5 UI deliverables strictly implement this exact layout and styling.
