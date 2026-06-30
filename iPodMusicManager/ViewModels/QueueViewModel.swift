import Foundation
import UserNotifications

@MainActor
final class QueueViewModel: ObservableObject {
    @Published var jobs: [ConversionJob] = []
    @Published var isRunning = false
    @Published var showQueue = false

    private var pipeline = ConversionPipeline()
    private var appleMusic = AppleMusicService()
    private var navidrome: NavidromeClient?
    private var recordStore: ImportRecordStore?
    private var runTask: Task<Void, Never>?

    func configure(navidrome: NavidromeClient, recordStore: ImportRecordStore? = nil) {
        self.navidrome = navidrome
        if let recordStore { self.recordStore = recordStore }
    }

    // MARK: - Queue management

    func enqueue(_ job: ConversionJob) {
        jobs.append(job)
        showQueue = true
    }

    func enqueue(tracks: [NavidromeTrack], playlistName: String? = nil) {
        tracks.forEach { enqueue(ConversionJob(track: $0, targetPlaylistName: playlistName)) }
    }

    func enqueueLocalFiles(_ urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == "flac" {
            let title = url.deletingPathExtension().lastPathComponent
            let fakeTrack = NavidromeTrack(
                id: url.path, title: title, artist: nil, artistId: nil,
                album: nil, albumId: nil, track: nil, discNumber: nil,
                year: nil, genre: nil, duration: nil, bitRate: nil,
                size: nil, coverArt: nil, suffix: "flac"
            )
            enqueue(ConversionJob(track: fakeTrack, localFlacURL: url))
        }
        showQueue = true
    }

    func removeJob(id: UUID) {
        guard !isRunning else { return }
        jobs.removeAll { $0.id == id }
    }

    func clearFinished() {
        jobs.removeAll { $0.isFinished }
    }

    func clearAll() {
        guard !isRunning else { return }
        jobs.removeAll()
    }

    // MARK: - Execution

    func start() {
        guard !isRunning else { return }
        isRunning = true
        runTask = Task { await processQueue() }
    }

    func pause() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
    }

    // MARK: - Private pipeline

    /// Tolerant index of the current library: match key → track database ID. Built once
    /// per run and updated as tracks are imported, so duplicate detection and playlist
    /// membership don't re-scan the library for every job.
    private var libraryIndex: [String: Int] = [:]

    private func processQueue() async {
        await buildLibraryIndex()
        for job in jobs where job.status == .queued {
            if Task.isCancelled { break }
            await processJob(job)
        }
        isRunning = false
        let done = jobs.filter { $0.status == .done }.count
        let failed = jobs.filter { $0.status == .failed }.count
        if done + failed > 0 { await sendNotification(done: done, failed: failed) }
    }

    private func buildLibraryIndex() async {
        guard let snapshot = await appleMusic.allLibraryTracks() else { return }
        var idx: [String: Int] = [:]
        for t in snapshot {
            let key = TrackMatch.key(title: t.title, artist: t.artist)
            if idx[key] == nil { idx[key] = t.databaseID }
        }
        libraryIndex = idx
    }

    private func processJob(_ job: ConversionJob) async {
        let tmpFlac = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).flac")

        defer { try? FileManager.default.removeItem(at: tmpFlac) }

        do {
            let matchKey = TrackMatch.key(title: job.track.title, artist: job.track.artist ?? "")

            // Duplicate detection (tolerant): if the track is already in the library,
            // don't re-import it — just make sure it's in the target playlist (no dup).
            if let existingID = libraryIndex[matchKey] {
                if let playlist = job.targetPlaylistName {
                    try? await appleMusic.addTrackToPlaylistByID(databaseID: existingID, playlistName: playlist)
                }
                job.status = .alreadyInLibrary
                return
            }

            let flacURL: URL
            if let local = job.localFlacURL {
                flacURL = local
            } else {
                guard let nav = navidrome else { throw QueueError.notConfigured }
                job.status = .downloading
                try await nav.downloadTrack(id: job.track.id, to: tmpFlac)
                job.downloadProgress = 1.0
                flacURL = tmpFlac
            }

            job.status = .converting
            let defaults = UserDefaults.standard
            let embedArt = defaults.object(forKey: "embedAlbumArt") as? Bool ?? true
            let format = OutputFormat(rawValue: defaults.string(forKey: "outputFormat") ?? "") ?? .aac
            let quality = QualityTier(rawValue: defaults.string(forKey: "outputQuality") ?? "") ?? .high
            let m4aURL = try await pipeline.convert(
                flacURL: flacURL, format: format, quality: quality, embedAlbumArt: embedArt
            ) { p in
                Task { @MainActor in job.convertProgress = p }
            }
            defer { try? FileManager.default.removeItem(at: m4aURL) }

            job.status = .importing
            // Apple Music silently ignores formats it can't import (e.g. FLAC): `add`
            // succeeds but returns no track. A nil ID means nothing landed.
            guard let newID = try await appleMusic.importTrack(m4aURL: m4aURL) else {
                throw QueueError.importRejected(format)
            }
            // Remember it so other jobs for the same track (in other playlists) treat it
            // as a duplicate instead of re-importing.
            libraryIndex[matchKey] = newID

            if let playlist = job.targetPlaylistName {
                try? await appleMusic.addTrackToPlaylistByID(databaseID: newID, playlistName: playlist)
            }

            // Record provenance + the settings used, so the track can be re-processed later.
            let source: ImportRecord.Source = job.localFlacURL.map { .local(path: $0.path) }
                ?? .navidrome(id: job.track.id)
            recordStore?.upsert(ImportRecord(
                title: job.track.title,
                artist: job.track.artist ?? "",
                source: source,
                format: format.rawValue,
                quality: quality.rawValue,
                embedAlbumArt: embedArt,
                importedAt: Date()
            ))

            job.status = .done

        } catch {
            job.status = .failed
            job.errorMessage = error.localizedDescription
        }
    }

    private func sendNotification(done: Int, failed: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Import Complete"
        content.body = "\(done) track\(done == 1 ? "" : "s") imported\(failed > 0 ? ", \(failed) failed" : "")."
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }
}

enum QueueError: LocalizedError {
    case notConfigured
    case importRejected(OutputFormat)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Navidrome client not configured"
        case .importRejected(let format):
            if format == .flac {
                return "Apple Music can't import FLAC. Choose Apple Lossless in Settings for lossless playback."
            }
            return "Apple Music rejected the \(format.label) file — it didn't appear in the library."
        }
    }
}
