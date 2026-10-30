<!-- impeccable:product-schema 1 -->
Platform: adaptive

## Users
Transkript Hub is built for journalists, researchers, students, podcasters, video editors, software engineers, and knowledge workers on macOS who process high volumes of spoken media (YouTube videos, playlists, channels, local video files, voice memos, meetings, and live audio recordings). They open the app to turn hours of audio or video into clean, searchable, time-synced transcripts in seconds—without uploading sensitive recordings to third-party cloud servers.

## Product Purpose
Eliminate the friction between recorded speech and usable text on macOS. Users paste a link, drop a video or audio file, or record live system/microphone audio, and immediately get an accurate, local AI transcript saved right where they need it.

## Positioning
A pro-grade native macOS transcription studio—combining the speed and keyboard-first ergonomics of Raycast and Linear with the tactile acoustic precision of Apple Logic Pro and Voice Memos. Unlike cloud-based transcription services that charge per minute, require uploads, and trap transcripts in web dashboards, Transkript Hub runs 100% locally on Apple Silicon (`whisper.cpp` Metal acceleration) and writes clean `.txt` files directly to the user's filesystem or next to the source video.

## Operating Context
Used primarily as a desktop studio utility and menu-bar companion on macOS 14+ (Sonoma / Sequoia). Sessions range from quick 5-second "paste link & copy transcript" bursts (`⌘V` -> `⌘⇧C`) to batch-ingesting 50-video YouTube playlists or monitoring iCloud Drive and Apple Voice Memos folders in the background while multitasking.

## Capabilities and Constraints
- **100% Local AI Engine**: Powered by `whisper.cpp` with Apple Silicon Metal GPU / Accelerate acceleration and dynamic model management (Tiny, Base, Small, Medium, Large-v3-Turbo, Q5 quantized).
- **Universal Media Ingestion**: YouTube single videos, playlists, and channels (`yt-dlp`), local audio (`.mp3`, `.m4a`, `.wav`, `.flac`, `.ogg`, `.aac`, `.opus`), and local video files (`.mp4`, `.mov`, `.m4v`, `.mkv`, `.avi`, `.webm`) with automatic audio extraction and adjacent `.txt` saving.
- **Dual-Source Live Capture**: Captures microphone (`AVAudioEngine`) and macOS system audio (`ScreenCaptureKit`) with proactive permission diagnostics.
- **Interactive Karaoke & Waveform Studio**: 60fps Metal-backed `Canvas` waveform scrubber synced to word-level karaoke highlighting, inline segment text editing, and speaker renaming.
- **Smart Deduplication & Cache**: SQLite-backed `TranscriptCacheManager` prevents redundant work and prompts the user when an already-transcribed item is re-submitted.

## Brand Commitments
- **Zero-Cloud Privacy**: Every byte of audio, video, and text stays on the user's Mac.
- **Native macOS Craft**: Real `NSVisualEffectView` Liquid Glass translucency, SF Pro & SF Mono typography with tabular numerals, and full keyboard shortcut mastery.
- **Muted Luxury Palette**: Curated mineral and metallic accents (`sapphirePro`, `champagneBronze`, `slateAzure`, `emeraldMineral`, `crimsonVelvet`, `obsidianTeal`, `cashmereViolet`, `terracotta`) over deep translucent surfaces—never garish neon or multi-layered card borders.

## Product Principles
1. **Immediate Action Over Configuration**: The main window opens directly into the 6-card Studio Control Bar and the Central Queue—no splash screens, no nested settings mazes.
2. **Filesystem First**: Transcripts are real files on disk (saved to the output folder or right next to the source video) as well as one-click clipboard actions (single item or combined batch session).
3. **Calm Precision Under Load**: Whether transcribing 1 voice memo or 40 playlist videos, progress indicators, tabular counters, and state badges remain stable, legible, and jitter-free.
4. **Honest & Recoverable States**: Missing macOS permissions (Microphone, Screen Recording, Full Disk Access) and network/extraction errors surface with clear explanations and one-click recovery actions.

## Accessibility & Inclusion
- Supports 5 interface languages (Turkish, English, German, French, Spanish) with instant live switching.
- Honours macOS system appearance, `@Environment(\.accessibilityReduceMotion)` for spring and pulse animations, VoiceOver `.accessibilityLabel` coverage on all icon-only controls, and full keyboard navigation (`⌘V`, `⌘O`, `⌘R`, `⌘⇧C`, `⌘A`, `Space`, `⌘←`, `⌘→`, `⌘Return`).
