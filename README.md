# iPod Music Manager

A native macOS app for converting your self-hosted [Navidrome](https://www.navidrome.org/) FLAC library into Apple Music — with full metadata, artwork, and automatic playlist sync.

---

## App Icons

<p align="center">
  <img src="iPodMusicManager/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" width="160" alt="Waveform icon" />
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="iPodMusicManager/Assets.xcassets/AppIcon-ClickWheel.appiconset/icon_512x512.png" width="160" alt="ClickWheel icon" />
</p>
<p align="center">
  <sub>Waveform (default) &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; ClickWheel</sub>
</p>

Switch icons in **Settings → General → App Icon**.

---

## Features

| | |
|---|---|
| **Navidrome browser** | Browse artists → albums → tracks with artwork, direct from your server |
| **FLAC → M4A pipeline** | ffmpeg (decode) + Apple's `afconvert` AAC encoder + full metadata/artwork injection |
| **Zero-copy import** | Every temp file is deleted the moment the track lands in Apple Music |
| **Linked playlist sync** | Mirror any Navidrome playlist to Apple Music — additions and removals — on a configurable timer |
| **Local FLAC drop** | Drag files or folders straight into the app as an alternative to browsing |
| **Queue panel** | Per-track progress: downloading → converting → importing |
| **History** | Log of every completed or failed conversion in the current session |

---

## Requirements

- macOS 14 Ventura or later
- [ffmpeg](https://formulae.brew.sh/formula/ffmpeg): `brew install ffmpeg`
- A running [Navidrome](https://www.navidrome.org/) instance (any version with Subsonic API)

---

## Installation

1. Download `iPod-Music-Manager-vX.X.zip` from [Releases](../../releases)
2. Unzip and drag **iPod Music Manager.app** to `/Applications`
3. Open the app → **Settings (⌘,)** → enter your Navidrome URL + credentials → **Save & Test**

---

## Building from source

```bash
# Prerequisites: Xcode 15+, xcodegen
brew install xcodegen

git clone https://github.com/SahilUX/iPod-Music-Manager
cd iPod-Music-Manager
xcodegen generate
open iPodMusicManager.xcodeproj
```

Set your **Team** in Signing & Capabilities, then `⌘R`.

---

## Workflow

```
Navidrome (FLAC)
    │
    ▼  download to $TMPDIR
ffmpeg -ar 44100 → PCM WAV
    │
    ▼
afconvert -f m4af -d aac -s 3 → AAC M4A
    │
    ▼
ffmpeg -map_metadata → inject FLAC tags into M4A
    │
    ▼  osascript
Apple Music library + playlist
    │
    ▼  cleanup
All temp files deleted
```

---

## Linked Playlist Sync

1. Go to **Linked Playlists** in the sidebar
2. Click **+** → pick a Navidrome playlist → name the Apple Music playlist → set sync interval
3. The app syncs immediately, then on your chosen schedule (15 min → 24 hr)
4. Tracks removed from the Navidrome playlist are removed from the Apple Music playlist on the next sync

---

## Releases

| Version | Notes |
|---|---|
| [v1.0](../../releases/tag/v1.0) | Initial release |

---

## Tech stack

- **SwiftUI** (macOS 14+) — NavigationSplitView, HSplitView, inspector panel
- **Subsonic REST API** — Navidrome library browsing and FLAC download
- **URLSession** async/await — networking
- **Process** — ffmpeg + afconvert shell invocation
- **osascript** — Apple Music control via AppleScript
- **Security framework** — Keychain credential storage
- **UserNotifications** — batch complete + playlist sync notifications
