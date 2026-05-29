# Design Document
## iPod Music Manager — macOS Application
**Version:** 1.0  
**Date:** 2026-05-29

---

## 1. Design Philosophy

- **Native first.** Looks and feels like a first-party Apple app. Uses standard macOS controls, sidebars, and typography — no custom widgets that fight the platform.
- **Progress, not configuration.** The primary screen is always the library browser or the active job. Settings are tucked away.
- **Zero cognitive load after setup.** Once the server is connected, the user should be able to go from "I want this album" to "it's in Apple Music" in three interactions: select → queue → go.

---

## 2. Visual Language

| Token | Value |
|---|---|
| Window style | `.sidebar` + content split view (NSNavigatorArea) |
| Accent color | System accent (user's chosen macOS accent) |
| Iconography | SF Symbols throughout |
| Typography | System font (SF Pro); no custom fonts |
| Corner radius | 8pt (cards), 6pt (badges) |
| Sidebar width | 220pt min, 280pt max |
| Density | macOS default row height (22pt list rows) |

---

## 3. App Layout

### 3.1 Window Structure

```
┌─────────────────────────────────────────────────────────────────────┐
│  Toolbar: [Server Status●] [Search] ──────────── [Settings ⚙] [▶ Go]│
├────────────┬──────────────────────────────┬────────────────────────┤
│  SIDEBAR   │       CONTENT AREA           │    QUEUE PANEL         │
│            │                              │  (slide-in, 280pt)     │
│  ● Artists │  Album grid or track list    │                        │
│  ● Albums  │  for selected artist/album   │  Track 1    ████░  72% │
│  ● Local   │                              │  Track 2    ░░░░░   0% │
│            │                              │  Track 3    ░░░░░   0% │
│  [Navidrome│                              │                        │
│   section] │                              │  [Pause]  [Cancel]     │
│  Artists   │                              │                        │
│  > Rihanna │                              │  3 tracks | ~45 MB     │
│  > Eminem  │                              │                        │
└────────────┴──────────────────────────────┴────────────────────────┘
```

### 3.2 Sidebar

Three sections:

1. **Local** — drag-drop target; shows queued local files
2. **Navidrome** — collapsible; shows Artists list when server connected; shows "Connect Server" prompt when not
3. **History** — last 7 days of completed imports (track name, date, ✓ or ✗)

### 3.3 Content Area — Artist View

```
╔═══════════════════════════════════════════════════════╗
║  Rihanna                                              ║
║  27 albums · 312 tracks                               ║
╠═══════════════════════════════════════════════════════╣
║  [Add All to Queue]                                   ║
╠═══════════════════════════════════════════════════════╣
║  ┌──────────┐  ┌──────────┐  ┌──────────┐            ║
║  │ [cover]  │  │ [cover]  │  │ [cover]  │            ║
║  │ Good Girl│  │ Loud     │  │ Rated R  │            ║
║  │ Gone Bad │  │ 2010     │  │ 2009     │            ║
║  │ 2007     │  │          │  │          │            ║
║  └──────────┘  └──────────┘  └──────────┘            ║
╚═══════════════════════════════════════════════════════╝
```

Albums shown as a 3-column grid. Already-imported albums have a small checkmark overlay on the cover.

### 3.4 Content Area — Album View

```
╔══╦══════════════════════════════════════════════════╗
║  ║  Loud — Rihanna — 2010                           ║
║[c║  11 tracks · 43:22 · [+ Add Album to Queue]      ║
║ov╠══════════════════════════════════════════════════╣
║er║  #   Title             Duration   Status         ║
║] ╠══════════════════════════════════════════════════╣
║  ║  1   Only Girl         3:57       ✓ In Library   ║
║  ║  2   What's My Name    3:44       + In Queue     ║
║  ║  3   Cheers            3:38       ─ Not synced   ║
║  ║  4   S&M               3:45       ─ Not synced   ║
╚══╩══════════════════════════════════════════════════╝
```

Track status badges:
- `✓ In Library` — green pill — already in Apple Music, skip
- `+ In Queue` — blue pill — currently queued
- `↓ Downloading` — orange pill — active
- `⚡ Converting` — yellow pill — conversion in progress
- `✗ Failed` — red pill — click to see error

Row right-click context menu: "Add to Queue", "Skip", "Copy Track Info"

### 3.5 Queue Panel (slide-in from right)

```
┌─────────────────────────────────────┐
│  Queue (5 tracks)          [Clear]  │
├─────────────────────────────────────┤
│  ▐███████████░░░░░░░░░▌  Diamonds   │
│  Rihanna · 3:45          72% ↓      │
│──────────────────────────────────── │
│  ░░░░░░░░░░░░░░░░░░░░░  Woo         │
│  Rihanna · 2:58                     │
│──────────────────────────────────── │
│  ░░░░░░░░░░░░░░░░░░░░░  Only Girl   │
│  Rihanna · 3:57                     │
├─────────────────────────────────────┤
│  ≈ 38 MB remaining                  │
│  [  Pause  ]        [  Cancel  ]    │
│         [ ▶ Start / Resume ]        │
└─────────────────────────────────────┘
```

Queue panel toggles from toolbar. Items can be dragged to reorder before start.

---

## 4. Key Interactions

### 4.1 First Launch / Setup

1. App opens to a welcome screen with two large cards:
   - **Connect Navidrome Server** → opens Settings panel, Navidrome tab
   - **Drop Local FLACs** → shows drop zone immediately

2. Settings panel — Navidrome tab:
   ```
   Server URL:  [https://music.example.com     ]
   Username:    [admin                          ]
   Password:    [••••••••                       ]
               [ Test Connection ]
   Status:      ● Connected — Navidrome 0.53.3
   ```

3. After successful connection, sidebar populates and welcome screen is replaced by the artist browser.

### 4.2 Queueing Music

- **Single track:** Click the `+` button at the end of a track row, or right-click → "Add to Queue"
- **Whole album:** Click "Add Album to Queue" button in the album header
- **Whole discography:** Click "Add All to Queue" in the artist view header
- **Local files:** Drag FLAC files or folders anywhere onto the app window

Queue panel slides in automatically when first item is added.

### 4.3 Running a Job

1. User clicks **▶ Start** in the queue panel.
2. Each track progresses through states: Downloading → Converting → Importing → Done / Failed.
3. Temp files deleted immediately after each track.
4. macOS notification fires when entire batch completes: "Imported 12 tracks to Apple Music ✓"
5. Queue clears automatically on full success; failed tracks stay listed with error detail.

### 4.4 Duplicate Handling

- Tracks already in Apple Music show `✓ In Library` badge.
- If user adds them to queue anyway, app shows a confirmation sheet:
  > "3 tracks are already in your Apple Music library. Skip them or import again?"
  > [ Skip Duplicates ] [ Import Anyway ]

---

## 5. Settings Panel

### General Tab
- ffmpeg path (auto-detected, override allowed)
- Temp directory (default: system temp)
- Toggle: "Show already-imported tracks in browser"
- Toggle: "Send notification on batch complete"

### Navidrome Tab
- URL, username, password (Keychain-backed)
- Test Connection button
- Library cache: "Last synced 2 min ago · [ Refresh Now ]"

### About Tab
- App version, ffmpeg version detected, macOS version

---

## 6. States & Edge Cases

| State | UI Treatment |
|---|---|
| No server configured | Welcome card + prompt; local drop still works |
| Server unreachable | Red dot in toolbar; sidebar shows "Reconnect" button; local drop still works |
| ffmpeg not found | Banner warning on launch with "Install via Homebrew" link; conversion blocked |
| Disk full mid-job | Error dialog; current track aborted cleanly; queue paused |
| Apple Music not open | App launches Apple Music automatically before first import |
| Network drops mid-download | Track marked failed; queue continues; retry button shown |

---

## 7. Accessibility

- All interactive elements have VoiceOver labels.
- Progress bars announce percentage via accessibility notifications.
- Status badges use both color and text (never color alone).
- Keyboard shortcut: `⌘R` to start/resume queue, `⌘.` to pause.

---

## 8. App Icon Concept

**Form factor:** macOS big-sur-style squircle, vibrant.

**Concept:** A waveform that transitions left-to-right — jagged FLAC-style peaks on the left morphing into smooth Apple-style sine wave on the right — against a deep music-purple-to-indigo gradient background. A subtle downward arrow below the waveform suggests downloading from server. The overall feel is confident, musical, and premium.

**See:** `ICON_PROMPT.md` for the AI image generation prompt.
