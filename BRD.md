# Business Requirements Document
## iPod Music Manager — macOS Application
**Version:** 1.0  
**Date:** 2026-05-29  
**Status:** Draft

---

## 1. Executive Summary

The user maintains a personal music server (Navidrome) containing a lossless FLAC library. The current workflow for getting music onto Apple Music involves several manual terminal steps: downloading FLACs, converting via ffmpeg + afconvert, importing into Apple Music, and deleting intermediary files. This process is error-prone, time-consuming, and offers no discoverability of what's already been synced. A native macOS application will collapse this multi-step CLI workflow into a single streamlined UI.

---

## 2. Business Problem

| Pain Point | Impact |
|---|---|
| 4-step manual CLI process per batch | 10–20 min of terminal work per session |
| No visibility into what's already in Apple Music | Risk of duplicates |
| Temp files left behind on failed runs | Wasted disk space |
| No way to browse the server library from the Mac | Must SSH or use Navidrome web UI to identify tracks |
| Metadata sometimes lost in conversion | Re-tagging required manually |

---

## 3. Business Objectives

1. **Reduce conversion workflow** from 4 manual steps to 1 click.
2. **Eliminate duplicate imports** by tracking sync state.
3. **Zero-copy principle:** no permanent local copies of FLACs; all intermediary files deleted automatically.
4. **Server-first discovery:** browse and select music directly from Navidrome without leaving the app.
5. **Lossless-to-Apple-Music pipeline** preserving all metadata and artwork.

---

## 4. Stakeholders

| Role | Person | Interest |
|---|---|---|
| End User / Owner | Sahil | Frictionless personal music management |
| Music Source | Navidrome server | Provides FLAC library via Subsonic API |
| Music Destination | Apple Music (local) | Receives M4A files with full metadata |

---

## 5. Scope

### In Scope
- Navidrome server connection and library browsing
- FLAC → WAV → M4A conversion pipeline (ffmpeg + afconvert)
- Metadata + artwork preservation
- One-click import to Apple Music library
- Automatic cleanup of all temp/intermediate files
- Sync state tracking (what's already imported)
- Local FLAC folder drag-and-drop as fallback input

### Out of Scope
- Uploading back to Navidrome
- Playlist management in Apple Music
- Any other audio format (MP3, OGG, etc.) — future consideration
- Windows / Linux support
- Modifying or deleting files on the Navidrome server

---

## 6. Success Criteria

- Full batch conversion + import completes without any manual intervention
- All metadata (title, artist, album, track #, artwork, lyrics) present in Apple Music after import
- Zero temp files remain on disk after successful or failed conversion
- Duplicate detection prevents re-importing a track already in Apple Music
- App connects to Navidrome and renders library within 3 seconds on local network

---

## 7. Constraints & Assumptions

- macOS 13 Ventura or later (required for modern SwiftUI + MusicKit APIs)
- ffmpeg must be installed (`/usr/local/bin/ffmpeg` or `/opt/homebrew/bin/ffmpeg`)
- Navidrome server is accessible via HTTP/HTTPS (Subsonic-compatible API)
- FLACs on the server are never deleted by this app — server is read-only from the app's perspective
- Apple Music / iTunes library is the local destination

---

## 8. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| ffmpeg not installed | Medium | App detects on launch and shows install instructions |
| Navidrome API auth changes | Low | Abstract API layer, configurable credentials |
| Apple Music scripting permissions revoked by macOS update | Low | Monitor MusicKit/AppleScript compatibility |
| Large FLAC download on slow connection | Medium | Progress indicator, cancellable downloads |
