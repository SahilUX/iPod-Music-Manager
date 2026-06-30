import Foundation
import UserNotifications

/// Re-applies the current format/quality/album-art settings to already-imported tracks.
///
/// - A change in **format or quality** requires re-converting from the lossless source,
///   so the track is re-downloaded (Navidrome) or read from disk (local), converted with
///   the current settings, and the Apple Music track is replaced in place (playlist
///   memberships are preserved).
/// - A change in **album art only** is applied in place via AppleScript — no re-download.
/// - Tracks whose lossless source can't be recovered are skipped.
@MainActor
final class LibraryReprocessor: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusText = ""
    @Published private(set) var lastSummary: String?
    @Published private(set) var isScanning = false
    @Published private(set) var scanSummary: String?

    private let navidrome: NavidromeClient
    private let pipeline: ConversionPipeline
    private let appleMusic: AppleMusicService
    private let store: ImportRecordStore

    init(navidrome: NavidromeClient, pipeline: ConversionPipeline,
         appleMusic: AppleMusicService, store: ImportRecordStore) {
        self.navidrome = navidrome
        self.pipeline = pipeline
        self.appleMusic = appleMusic
        self.store = store
    }

    // MARK: - Scan: reconcile records with the real Apple Music library

    /// Reads the Apple Music library, infers each track's current format/quality/art,
    /// and matches it to a Navidrome source so it becomes re-sourceable. Existing
    /// records (e.g. local imports) keep their source if no Navidrome match is found.
    func scanLibrary() async {
        guard !isScanning, !isRunning else { return }
        isScanning = true
        scanSummary = nil
        statusText = "Reading Apple Music library…"
        defer { isScanning = false; statusText = "" }

        guard let tracks = await appleMusic.allLibraryTracks() else {
            scanSummary = "Couldn't read the Apple Music library."
            return
        }
        guard !tracks.isEmpty else { scanSummary = "No tracks found in Apple Music."; return }

        // Build a Navidrome (title|artist) → id map for matching.
        statusText = "Matching against Navidrome…"
        var navMap: [String: String] = [:]
        if navidrome.isConnected, let songs = try? await navidrome.getAllSongs(count: 10000) {
            for s in songs {
                navMap[ImportRecord.key(title: s.title, artist: s.artist ?? "")] = s.id
            }
        }

        var matched = 0, unsourceable = 0
        for t in tracks {
            guard let fmt = Self.inferFormat(kind: t.kind) else { continue }
            let key = ImportRecord.key(title: t.title, artist: t.artist)

            // Determine a source: Navidrome match wins; else preserve an existing record's source.
            let source: ImportRecord.Source?
            if let id = navMap[key] {
                source = .navidrome(id: id)
            } else if let existing = store.records.first(where: { $0.id == key }) {
                source = existing.source
            } else {
                source = nil
            }
            guard let source else { unsourceable += 1; continue }

            store.upsert(ImportRecord(
                title: t.title,
                artist: t.artist,
                source: source,
                format: fmt.rawValue,
                quality: Self.inferQuality(bitRate: t.bitRate).rawValue,
                embedAlbumArt: t.hasArtwork,
                importedAt: Date()
            ))
            matched += 1
        }

        scanSummary = "\(matched) re-sourceable track\(matched == 1 ? "" : "s") found"
            + (unsourceable > 0 ? ", \(unsourceable) without a source" : "")
            + (navidrome.isConnected ? "." : " (connect Navidrome to match more).")
    }

    private static func inferFormat(kind: String) -> OutputFormat? {
        let k = kind.lowercased()
        if k.contains("lossless") { return .alac }
        if k.contains("flac")     { return .flac }
        if k.contains("aac")      { return .aac }
        if k.contains("mpeg") || k.contains("mp3") { return .mp3 }
        return nil  // WAV/AIFF/unknown — not a format we target
    }

    private static func inferQuality(bitRate: Int) -> QualityTier {
        if bitRate >= 288 { return .maximum }   // ~320
        if bitRate >= 224 { return .high }       // ~256
        if bitRate >= 160 { return .medium }     // ~192
        return .low                              // ~128
    }

    private enum Action { case upToDate, artInPlace, reconvert }

    /// What the current settings would do to a given record.
    private func action(for record: ImportRecord,
                        format: OutputFormat, quality: QualityTier, embedArt: Bool) -> Action {
        let formatChanged = record.format != format.rawValue
        let qualityChanged = format.isLossy && record.quality != quality.rawValue
        if formatChanged || qualityChanged { return .reconvert }
        if record.embedAlbumArt != embedArt { return .artInPlace }
        return .upToDate
    }

    /// Number of tracks that differ from the current settings (for the UI).
    func outdatedCount(format: OutputFormat, quality: QualityTier, embedArt: Bool) -> Int {
        store.records.filter {
            action(for: $0, format: format, quality: quality, embedArt: embedArt) != .upToDate
        }.count
    }

    func reprocessAll(format: OutputFormat, quality: QualityTier, embedArt: Bool) async {
        guard !isRunning else { return }
        guard format != .flac else {
            lastSummary = "Apple Music can't import FLAC — choose Apple Lossless to re-process."
            return
        }
        isRunning = true
        lastSummary = nil
        progress = 0
        defer { isRunning = false; statusText = "" }

        let targets = store.records.filter {
            action(for: $0, format: format, quality: quality, embedArt: embedArt) != .upToDate
        }
        guard !targets.isEmpty else { lastSummary = "Everything is already up to date."; return }

        var reconverted = 0, artUpdated = 0, skipped = 0, failed = 0

        for (i, record) in targets.enumerated() {
            progress = Double(i) / Double(targets.count)
            statusText = "\(record.title) — \(record.artist)"
            do {
                switch action(for: record, format: format, quality: quality, embedArt: embedArt) {
                case .upToDate:
                    continue
                case .artInPlace:
                    if try await updateArtInPlace(record, embedArt: embedArt) {
                        artUpdated += 1
                    } else {
                        skipped += 1
                    }
                case .reconvert:
                    if try await reconvert(record, format: format, quality: quality, embedArt: embedArt) {
                        reconverted += 1
                    } else {
                        skipped += 1
                    }
                }
            } catch {
                failed += 1
            }
        }

        progress = 1
        var parts: [String] = []
        if reconverted > 0 { parts.append("\(reconverted) re-converted") }
        if artUpdated > 0  { parts.append("\(artUpdated) art updated") }
        if skipped > 0     { parts.append("\(skipped) skipped (no source)") }
        if failed > 0      { parts.append("\(failed) failed") }
        lastSummary = parts.isEmpty ? "Nothing to do." : parts.joined(separator: ", ") + "."
        await notify(summary: lastSummary ?? "")
    }

    // MARK: - Album art in place

    /// Returns true if art was actually updated; false if it had to be skipped.
    private func updateArtInPlace(_ record: ImportRecord, embedArt: Bool) async throws -> Bool {
        if !embedArt {
            try await appleMusic.removeArtwork(title: record.title, artist: record.artist)
            commit(record, embedArt: false)
            return true
        }

        // Need image data to embed.
        let imageData: Data?
        switch record.source {
        case .navidrome(let id):
            guard navidrome.isConnected, let url = navidrome.coverArtURL(id: id, size: 1024) else { return false }
            imageData = try? await URLSession.shared.data(from: url).0
        case .local(let path):
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { return false }
            imageData = await pipeline.extractCoverArt(from: url)
        }
        guard let data = imageData, !data.isEmpty else { return false }

        try await appleMusic.setArtwork(title: record.title, artist: record.artist, imageData: data)
        commit(record, embedArt: true)
        return true
    }

    // MARK: - Full re-convert + replace

    /// Returns true if the track was re-converted and replaced; false if source was unavailable.
    private func reconvert(_ record: ImportRecord,
                           format: OutputFormat, quality: QualityTier, embedArt: Bool) async throws -> Bool {
        // 1. Obtain the lossless source.
        let flacURL: URL
        var tempFlac: URL?
        switch record.source {
        case .navidrome(let id):
            guard navidrome.isConnected else { return false }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).flac")
            try await navidrome.downloadTrack(id: id, to: tmp)
            flacURL = tmp
            tempFlac = tmp
        case .local(let path):
            guard FileManager.default.fileExists(atPath: path) else { return false }
            flacURL = URL(fileURLWithPath: path)
        }
        defer { if let t = tempFlac { try? FileManager.default.removeItem(at: t) } }

        // 2. Convert with the new settings.
        let outURL = try await pipeline.convert(
            flacURL: flacURL, format: format, quality: quality, embedAlbumArt: embedArt, progress: { _ in }
        )
        defer { try? FileManager.default.removeItem(at: outURL) }

        // 3. Replace SAFELY: import the new file first and confirm a genuinely new track
        //    landed, and only then delete the old one (by its database ID, so the new
        //    track is untouched). If nothing new arrived — e.g. Apple Music rejected the
        //    format — we abort without deleting, so the existing track is never lost.
        let playlists = await appleMusic.playlistsContaining(title: record.title, artist: record.artist)
        let oldIDs = Set(await appleMusic.trackDatabaseIDs(title: record.title, artist: record.artist))
        // Import returns the new track's ID, or nil if Apple Music rejected the format.
        // Only delete the old track once a new one is positively confirmed, so the
        // existing track is never lost.
        guard let newID = try await appleMusic.importTrack(m4aURL: outURL) else {
            throw QueueError.importRejected(format)
        }
        for id in oldIDs where id != newID {
            try? await appleMusic.deleteTrackByDatabaseID(id)
        }
        for name in playlists {
            try? await appleMusic.addTrackToPlaylistByID(databaseID: newID, playlistName: name)
        }

        // 4. Record the new settings.
        var updated = record
        updated.format = format.rawValue
        updated.quality = quality.rawValue
        updated.embedAlbumArt = embedArt
        store.upsert(updated)
        return true
    }

    private func commit(_ record: ImportRecord, embedArt: Bool) {
        var updated = record
        updated.embedAlbumArt = embedArt
        store.upsert(updated)
    }

    private func notify(summary: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Library Re-process Complete"
        content.body = summary
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }
}
