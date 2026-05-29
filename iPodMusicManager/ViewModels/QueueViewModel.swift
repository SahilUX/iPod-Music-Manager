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
    private var runTask: Task<Void, Never>?

    func configure(navidrome: NavidromeClient) {
        self.navidrome = navidrome
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

    private func processQueue() async {
        for job in jobs where job.status == .queued {
            if Task.isCancelled { break }
            await processJob(job)
        }
        isRunning = false
        let done = jobs.filter { $0.status == .done }.count
        let failed = jobs.filter { $0.status == .failed }.count
        if done + failed > 0 { await sendNotification(done: done, failed: failed) }
    }

    private func processJob(_ job: ConversionJob) async {
        let tmpFlac = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).flac")

        defer { try? FileManager.default.removeItem(at: tmpFlac) }

        do {
            // Duplicate detection
            let alreadyIn = await appleMusic.isTrackInLibrary(
                title: job.track.title, artist: job.track.artist ?? ""
            )
            if alreadyIn {
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
            let m4aURL = try await pipeline.convert(flacURL: flacURL) { p in
                Task { @MainActor in job.convertProgress = p }
            }
            defer { try? FileManager.default.removeItem(at: m4aURL) }

            job.status = .importing
            try await appleMusic.importTrack(m4aURL: m4aURL)

            if let playlist = job.targetPlaylistName {
                try await appleMusic.addTrackToPlaylist(
                    title: job.track.title,
                    artist: job.track.artist ?? "",
                    playlistName: playlist
                )
            }

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
    var errorDescription: String? { "Navidrome client not configured" }
}
