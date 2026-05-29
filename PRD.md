# Product Requirements Document
## iPod Music Manager — macOS Application
**Version:** 1.0  
**Date:** 2026-05-29  
**Status:** Draft

---

## 1. Product Overview

iPod Music Manager is a native macOS application that bridges a Navidrome self-hosted music server with Apple Music. It provides a browse-select-convert-import pipeline that is fully automated after the user makes their track selection. All intermediate files are ephemeral; the only permanent outputs are entries in the local Apple Music library.

---

## 2. User Stories

### P0 — Must Have

| ID | Story |
|---|---|
| US-01 | As a user, I can connect to my Navidrome server with a URL + credentials so I can browse my library |
| US-02 | As a user, I can browse artists, albums, and tracks from my Navidrome library |
| US-03 | As a user, I can select one or more tracks/albums/artists and queue them for conversion |
| US-04 | As a user, I can start a conversion job that downloads FLAC → converts to M4A → imports to Apple Music → deletes all temp files, automatically |
| US-05 | As a user, I can see real-time progress (download %, conversion progress, import status) for each track |
| US-06 | As a user, metadata (title, artist, album, genre, track#, disc#, year, artwork, lyrics) is present in Apple Music after import |
| US-07 | As a user, temp WAV and downloaded FLAC files are deleted immediately after each track completes (success or failure) |

### P1 — Should Have

| ID | Story |
|---|---|
| US-08 | As a user, tracks already present in my Apple Music library are visually marked so I don't re-import them |
| US-09 | As a user, I can drag local FLAC files into the app as an alternative to browsing Navidrome |
| US-10 | As a user, I can see a conversion log with per-track success/failure status |
| US-11 | As a user, I receive a macOS notification when a batch job completes |
| US-12 | As a user, my server credentials and settings are persisted in Keychain / UserDefaults |

### P2 — Nice to Have

| ID | Story |
|---|---|
| US-13 | As a user, I can search across my Navidrome library by title, artist, or album |
| US-14 | As a user, I can see album artwork thumbnails while browsing |
| US-15 | As a user, I can filter the Navidrome library to show only tracks not yet in Apple Music |
| US-16 | As a user, I can see estimated disk space needed before starting a batch |
| US-17 | As a user, failed conversions are retried automatically once |

---

## 3. Functional Requirements

### 3.1 Server Connection

- **FR-01:** App presents a settings panel for Navidrome URL, username, and password.
- **FR-02:** Credentials stored in macOS Keychain, not UserDefaults.
- **FR-03:** App performs a `ping` call to Navidrome on first launch and on manual reconnect.
- **FR-04:** Connection status shown persistently in the toolbar (green dot = connected, red = unreachable).
- **FR-05:** App supports both HTTP and HTTPS endpoints.

### 3.2 Library Browsing

- **FR-06:** App fetches and displays the full artist list from Navidrome (`getArtists` Subsonic endpoint).
- **FR-07:** Selecting an artist fetches and displays their albums (`getArtist`).
- **FR-08:** Selecting an album fetches and displays tracks (`getAlbum`).
- **FR-09:** Each track row shows: track number, title, duration, bitrate/format, and sync status badge.
- **FR-10:** App supports search via Navidrome's `search3` endpoint.
- **FR-11:** Album artwork is fetched lazily from Navidrome's `getCoverArt` endpoint and cached in-memory.

### 3.3 Queue & Conversion Pipeline

- **FR-12:** User can add individual tracks, full albums, or full artist discographies to the queue.
- **FR-13:** Queue is displayed as an ordered list with drag-to-reorder.
- **FR-14:** Starting the job processes the queue sequentially (one track at a time to avoid disk/CPU overload).
- **FR-15:** Per-track pipeline:
  1. Download FLAC from Navidrome (`download` endpoint) to `$TMPDIR`
  2. Decode FLAC → WAV: `ffmpeg -i input.flac -ar 44100 -y output.wav`
  3. Encode WAV → M4A: `afconvert -f m4af -d aac -s 3 -u pgcm 2 input.wav output.m4a`
  4. Inject metadata from FLAC into M4A: `ffmpeg -i output.m4a -i input.flac -map 0:a -map_metadata 1 -c copy final.m4a`
  5. Import `final.m4a` into Apple Music via MusicKit / AppleScript
  6. Delete: downloaded FLAC, intermediate WAV, intermediate M4A, final M4A
- **FR-16:** If any step fails, all temp files for that track are cleaned up and the error is logged; remaining queue continues.
- **FR-17:** User can pause or cancel the queue at any time; in-progress track completes cleanly before stopping.

### 3.4 Apple Music Integration

- **FR-18:** App adds the final M4A to Apple Music using `MusicKit` (preferred) or AppleScript as fallback.
- **FR-19:** After successful import, the local M4A file is deleted — Apple Music's own copy is the only remaining file.
- **FR-20:** Duplicate detection: before importing, app checks Apple Music library for a track with matching title + artist; if found, skips and marks as "Already in Library".

### 3.5 Local FLAC Input (Fallback)

- **FR-21:** User can drag one or more FLAC files (or a folder of FLACs) onto the app to queue them.
- **FR-22:** Local FLAC pipeline skips the download step; source FLAC is read in place.
- **FR-23:** After successful import to Apple Music, the source local FLAC is **not** deleted (it may be the server's authoritative copy on a mounted drive).

### 3.6 Settings

- **FR-24:** ffmpeg path is auto-detected at `/opt/homebrew/bin/ffmpeg` and `/usr/local/bin/ffmpeg`; user can override.
- **FR-25:** Option to set a custom temp directory (default: `$TMPDIR`).
- **FR-26:** Toggle: show/hide already-imported tracks in browser.

---

## 4. Non-Functional Requirements

| Category | Requirement |
|---|---|
| Performance | Library of 10,000 tracks loads within 5 seconds on LAN |
| Performance | Conversion of a 5-minute FLAC completes within 30 seconds |
| Reliability | App recovers gracefully from network interruption mid-download |
| Security | Credentials stored in Keychain, never logged |
| Compatibility | macOS 13 Ventura and later |
| Disk safety | No temp file survives a completed job (success or failure) |
| Accessibility | VoiceOver labels on all interactive elements |

---

## 5. Technical Architecture

```
┌─────────────────────────────────────────────────┐
│                  SwiftUI Layer                  │
│  LibraryBrowser | Queue View | Progress View    │
└────────────────────┬────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────┐
│               ViewModel Layer                   │
│  NavidromeViewModel | ConversionViewModel       │
│  QueueViewModel | MusicLibraryViewModel         │
└──────┬───────────────────────┬──────────────────┘
       │                       │
┌──────▼──────┐        ┌───────▼────────┐
│  Navidrome  │        │  Conversion    │
│  API Client │        │  Pipeline      │
│  (Subsonic) │        │  (Process)     │
└──────┬──────┘        └───────┬────────┘
       │                       │
  HTTP/HTTPS              ffmpeg +
  REST API                afconvert
                               │
                    ┌──────────▼─────────┐
                    │  Apple Music       │
                    │  MusicKit /        │
                    │  AppleScript       │
                    └────────────────────┘
```

### Key Components

| Component | Technology |
|---|---|
| UI Framework | SwiftUI (macOS 13+) |
| Networking | URLSession + async/await |
| Navidrome API | Subsonic REST API (JSON mode) |
| Audio Conversion | Process (ffmpeg + afconvert shell calls) |
| Apple Music Import | MusicKit framework + AppleScript fallback |
| Credential Storage | Security framework (Keychain) |
| Disk Cleanup | FileManager with defer blocks |
| Notifications | UserNotifications framework |

---

## 6. Milestones

| Phase | Features | Target |
|---|---|---|
| v0.1 — Core | Local FLAC drag-and-drop, conversion pipeline, Apple Music import | Week 1 |
| v0.2 — Server | Navidrome connection, artist/album/track browse | Week 2 |
| v0.3 — Polish | Search, sync badges, artwork thumbnails, notifications | Week 3 |
| v1.0 — Release | All P0 + P1 stories, full testing | Week 4 |
