# Transkript Hub — Design System & Architecture Standards (design.md)
*Version: 2026.1 • Standard: Apple HIG & Liquid Glass • Principle: Anti-AI Slop & Action-Oriented Desktop Architecture*

---

## 1. Core Philosophy: Anti-AI Slop & Human-Centric Desktop Ergonomics

Default AI design reflexes (treating every item equally, enclosing everything inside nested boxes, center-aligning all elements, and presenting passive statistics) are strictly forbidden in this system.

1. **Action-Oriented Information Architecture (Not Passive Feature Lists):**
   - Instead of passive database counters like *"Total 31 Videos"*, the UI presents actionable insight within the first two seconds:
     `"29 Completed • 2 Failed Videos (Retry) • 1 Watched Folder Active"`
   - Failed items (`[FAILED]`) are pinned to the top of the queue in an **"Action Required"** group with amber/red Liquid Glass highlights.
2. **Double-Nesting Prohibition:**
   - No bordered card within a bordered card (prohibition of padding over padding).
   - Grouping is achieved via 13pt typographic hierarchy, intentional negative whitespace, and 1px hairline dividers.
3. **Zero-Touch Ingestion & Confidence UI:**
   - Copying a YouTube URL or saving an audio recording to iCloud Drive / Voice Memos is detected with zero clicks.
   - Newly discovered items are displayed on the timeline with a *"Newly Discovered • Pending"* badge for instant reassurance.
4. **Single-Term & Behavioral Consistency:**
   - Every action uses consistent terminology across the entire app (e.g., "Transcribe Queue").

---

## 2. The 8-State Matrix

| State | Design & Behavioral Rule | Transkript Hub Implementation |
|---|---|---|
| **1. Empty (Initial)** | Full-screen focus, minimalist icon directing to a primary action. | "Queue is empty. Paste a YouTube link or drag an audio file." |
| **2. Loading** | Skeleton loading or real-time step progress bar. | "Processing 29/31 videos... Decoding audio (GPU Metal)." |
| **3. Success** | Color-coded badge with instant access to output actions. | Green glass badge, one-click "Copy" and "Show in Finder" buttons. |
| **4. Error (Partial / Full)** | Clear error card explaining root cause with an actionable exit path. | `[FAILED: 403 / Download Error]` -> "Update cookies or Retry with 1-click" |
| **5. No Results** | Suggestion and reset action when search/filter returns empty. | "No matching keywords found. Reset Filter (Esc)." |
| **6. Disabled** | Micro-tooltip explaining why an inactive button cannot be clicked. | Inactive "Transcribe Queue" button when queue is empty -> "Add at least 1 link or audio file first." |
| **7. Confirmation / Undo** | 5-second "Undo" toast capsule instead of disruptive modal dialogs. | Floating `Undo` capsule appears when queue is cleared. |
| **8. Recovery** | Automatic state recovery following unexpected terminations. | SQLite state machine resumes processing from the exact interrupted item. |

---

## 3. Liquid Glass UI Physics

Apple's modern Liquid Glass design language is implemented with the following specifications:

1. **H / 2 Capsule Geometry (Corner Radius Rule):**
   - Floating action buttons, status badges, and filter pills use a corner radius equal to exactly half their height:
     - `Height: 44pt` -> `CornerRadius: 22pt`
     - `Height: 36pt` -> `CornerRadius: 18pt`
     - `Height: 28pt` -> `CornerRadius: 14pt`
     - `Height: 20pt` -> `CornerRadius: 10pt`
2. **Refraction, Frost & 1px Specular Border Glow:**
   - Backgrounds refract light using `.ultraThinMaterial`.
   - Top and leading edges feature a 1px specular light highlight:
     `LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.08), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)`
3. **Dynamic Hug Contents:**
   - Buttons and status pills dynamically expand and contract using `.spring(response: 0.35, dampingFraction: 0.78)` animations as text changes.
4. **Ambient Drop Shadow:**
   - Soft depth shadow:
     `.shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)`

---

## 4. Typography & Layout System (13pt Desktop Standard)

macOS desktop ergonomics are anchored on a 13pt body baseline:

- **Large Header:** 18pt • Bold • `.system(size: 18, weight: .bold, design: .default)`
- **Subheader / Section Label:** 11pt • Semibold • Uppercase • Tracking: 0.8pt • `.secondary`
- **Body Text:** 13pt • Regular • LineSpacing: 3pt
- **Transcript Reader:** 13pt–22pt dynamic • Serif (`.serif` or `.system(..., design: .serif)`) • LineSpacing: 6pt
- **Metadata / Timestamps / Counters:** 11pt • Monospaced • `.system(size: 11, weight: .medium, design: .monospaced)`
- **Micro Badge / Label:** 10pt • Semibold • `.system(size: 10, weight: .semibold)`

---

## 5. Dual-Axis macOS Layout (3-Column NavigationSplitView)

```text
┌─────────────────┬──────────────────────────────┬───────────────────────────────────────────┐
│ COLUMN 1:SIDEBAR│ COLUMN 2: CONTENT & QUEUE    │ COLUMN 3: TRANSCRIPT READER & INSPECTOR   │
│                 │                              │                                           │
│ ◉ Transkript    │ [Actionable Header: 29/2/1]  │ [Liquid Glass Header: Title & Actions]    │
│                 │ ┌──────────────────────────┐ │                                           │
│ • Queue (31)    │ │ ⚠️ ACTION REQUIRED (2)   │ │ "Search in text..."       [A-] [A+] [Copy]│
│ • History       │ │  (Amber Liquid Glass)    │ │                                           │
│ • Watched Folder│ └──────────────────────────┘ │ ───────────────────────────────────────── │
│ • Settings      │ ┌──────────────────────────┐ │                                           │
│                 │ │ PROCESSING & QUEUE (1)   │ │  "Transcript content formatted in serif   │
│ 🟢 Folder Live  │ │ COMPLETED (28)           │ │   typography for fluid, effortless        │
│                 │ └──────────────────────────┘ │   reading..."                             │
│                 │ [⌘K Palette • Density Mode]  │                                           │
└─────────────────┴──────────────────────────────┴───────────────────────────────────────────┘
```

---

## 6. Keyboard-First Ergonomics

- <kbd>⌘</kbd> + <kbd>K</kbd> : Floating Liquid Glass Command Palette
- <kbd>⌘</kbd> + <kbd>V</kbd> : Zero-touch paste all valid links from clipboard into queue
- <kbd>⌘</kbd> + <kbd>Return</kbd> : Start Queue Transcription
- <kbd>⇧</kbd> + <kbd>⌘</kbd> + <kbd>C</kbd> : Copy clean transcript text to clipboard
- <kbd>Space</kbd> : Quick Look preview for audio recording / source media
- <kbd>Esc</kbd> : Dismiss search, floating palette, or clear filter
