# Transkript Hub 🎙️⚡

<p align="center">
  <a href="https://github.com/Akifulutas/Transkript-Hub/releases/latest/download/TranskriptHub.dmg">
    <img src="https://img.shields.io/badge/📥_Download_Transkript_Hub-macOS_(Apple_Silicon)-007AFF?style=for-the-badge&logo=apple&logoColor=white" alt="Download Transkript Hub for macOS">
  </a>
  <br>
  <sub>⚡ Tek tıkla indirin • Apple Silicon (M1/M2/M3/M4) • Sıfır Terminal • %100 Çevrimdışı</sub>
</p>

**Fully Local, Offline, Zero-Dependency Audio & Video Transcription Studio for Apple Silicon Macs.**

Transkript Hub transcribes YouTube videos (individual links, playlists, channels) and local audio files (Voice Memos, M4A, MP3, WAV, AAC, etc.) by leveraging your Mac's Apple Silicon GPU (Metal) directly. It sends **no audio to external servers** and requires **zero external installations** — no Buzz, Python, FFmpeg, Homebrew, or Terminal setup.

---

## ✨ Features

- **⚡ Apple Silicon Metal Acceleration:** Runs the official `whisper.cpp` C/C++ engine directly on the Mac GPU with Unified Memory architecture (10x–20x real-time transcription speeds).
- **🚫 Zero External Dependencies:** No Python, Homebrew, FFmpeg, or command-line tools required. Download a single DMG and run.
- **🛡️ Resilient Batch Processing (22/25 Resiliency):** In a playlist of 25 videos, if 3 fail due to regional or membership restrictions (e.g., HTTP 403), the process never aborts. All successful transcripts are automatically merged and formatted into a unified document or saved as individual files.
- **👁️ Real-Time Live Streaming Preview:** Words decoded via the Metal GPU are displayed live as transcription progresses, rather than waiting for completion.
- **🧠 Smart Deduplication & Duration Matching:** Never wastes time re-transcribing files. Identifies previously transcribed files through database cache matching file name, audio duration ($\pm1.0$s tolerance), and external YouTube IDs.
- **📋 Smart Clipboard Monitor:** Automatically detects YouTube links copied to your macOS clipboard (Safari, Chrome, Arc, etc.) and offers zero-touch queueing without interfering with password managers.
- **📁 Watched Folders & Cloud Sync:** Monitors designated local folders and iCloud Drive (`Transkript`). Automatically detects `.icloud` dateless placeholders and initiates immediate background downloads.
- **🎙️ Voice Memos & Apple Ecosystem Support:** Seamlessly integrates with iPhone and Apple Watch Voice Memos with macOS Full Disk Access auto-detection.
- **🔍 In-App Whisper Model Catalog:** Search, manage, and download official whisper.cpp models (`large-v3-turbo`, `medium`, `small`, `base`, `tiny`) with a single click.
- **💾 Atomic & Collision-Free Output:** Transcripts are written atomically (`Title.txt`). Existing files are never overwritten (`Title (2).txt`).
- **🌐 Multilingual UI:** Native support for English, German, and Turkish.
- **🔒 100% On-Device Privacy:** All audio decoding, downloading, and transcription runs strictly on your local machine.

---

## 🚀 Getting Started / Başlangıç

### 🇹🇷 Tek Tıkla Kolay Kurulum
1. Yukarıdaki mavi **Download Transkript Hub** butonuna tıklayarak (veya [GitHub Releases](../../releases) sayfasından) en güncel **`TranskriptHub.dmg`** dosyasını indirin.
2. İndirilen DMG dosyasını açın ve **Transkript Hub** uygulamasını **Applications (Uygulamalar)** klasörünüze sürükleyin.
3. Uygulamayı çalıştırın.
   - *Not:* macOS ilk açılışta güvenlik uyarısı verirse, uygulamaya sağ tıklayıp **Aç (Open)** deyin veya *Sistem Ayarları > Gizlilik ve Güvenlik* altından izin verin.
4. Hepsi bu kadar! Ses dosyalarınızı sürükleyip bırakabilir veya YouTube bağlantılarınızı ekleyebilirsiniz.

### 🇬🇧 1-Click Installation
1. Click the blue **Download Transkript Hub** button above (or download from [GitHub Releases](../../releases)) to get **`TranskriptHub.dmg`**.
2. Open the DMG and drag **Transkript Hub** into your **Applications** folder.
3. Launch **Transkript Hub**.
   - *Note:* If macOS Gatekeeper displays a prompt on first launch: Right-click the app and choose **Open**, or allow it under *System Settings > Privacy & Security*.
4. You are ready to transcribe!

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
| <kbd>⌘</kbd> + <kbd>1</kbd> | Switch to Queue View |
| <kbd>⌘</kbd> + <kbd>2</kbd> | Switch to History View |
| <kbd>⌘</kbd> + <kbd>3</kbd> | Switch to Watched Folder View |
| <kbd>⌘</kbd> + <kbd>A</kbd> | Select All Queue Items |
| <kbd>⇧</kbd> + <kbd>⌘</kbd> + <kbd>B</kbd> | Toggle Clipboard Monitoring |

---

## 🏗️ Architecture

```
TranskriptHub
├── TranskriptHubApp (SwiftUI 6 Interface, Menu Bar Mini Window & Settings)
└── TranskriptHubCore (Pure Swift Core Library)
    ├── Audio (AVFoundation 16kHz mono Float32 decoder & audio validator)
    ├── Transcription (whisper.xcframework Metal GPU engine & ModelManager)
    ├── Cache (TranscriptCacheManager smart deduplication & recovery)
    ├── Tools (Self-contained, sandboxed yt-dlp & Deno process runners)
    ├── Database (GRDB.swift SQLite persistent state machine & crash recovery)
    ├── Batch (BatchAssembler, OutputFormatter Format-Version 1)
    ├── Permissions (FullDiskAccessHelper multi-probe inspection)
    └── System (ClipboardMonitor, FolderWatcher)
```

---

## 🛠️ Building from Source

### Prerequisites

- macOS 14.0+ (Sonoma or Sequoia)
- Apple Silicon Mac (M1 / M2 / M3 / M4)
- Xcode 16+ or Swift 6 toolchain

### Build Commands

```bash
# Clone the repository
git clone https://github.com/Akifulutas/Transkript-Hub.git
cd Transkript-Hub

# Run the test suite (138 unit & integration tests)
swift test

# Build release binaries and bundle DMG
./scripts/package_dmg.sh
```

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
Third-party components (`whisper.cpp`, `GRDB.swift`, `yt-dlp`, `Deno`) remain subject to their respective open-source licenses.
