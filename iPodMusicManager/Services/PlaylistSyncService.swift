import Foundation
import UserNotifications

@MainActor
final class PlaylistSyncService: ObservableObject {
    @Published var links: [PlaylistLink] = []

    private let navidrome: NavidromeClient
    private let pipeline: ConversionPipeline
    private let appleMusic: AppleMusicService
    private let queueVM: QueueViewModel
    private var timers: [String: Task<Void, Never>] = [:]

    private let storageKey = "com.sahil.ipm.playlistLinks"

    init(navidrome: NavidromeClient, pipeline: ConversionPipeline, appleMusic: AppleMusicService, queueVM: QueueViewModel) {
        self.navidrome = navidrome
        self.pipeline = pipeline
        self.appleMusic = appleMusic
        self.queueVM = queueVM
        load()
        links.filter(\.autoSync).forEach { startTimer(for: $0) }
    }

    // MARK: - CRUD

    func addLink(_ link: PlaylistLink) {
        guard !links.contains(where: { $0.id == link.id }) else { return }
        links.append(link)
        save()
        if link.autoSync { startTimer(for: link) }
    }

    func removeLink(id: String) {
        stopTimer(id: id)
        links.removeAll { $0.id == id }
        save()
    }

    func updateLink(_ link: PlaylistLink) {
        guard let idx = links.firstIndex(where: { $0.id == link.id }) else { return }
        links[idx] = link
        save()
        stopTimer(id: link.id)
        if link.autoSync && link.isEnabled { startTimer(for: link) }
    }

    func resetSync(id: String) {
        guard let idx = links.firstIndex(where: { $0.id == id }) else { return }
        links[idx].syncedTrackIds = []
        links[idx].syncedTrackInfo = [:]
        links[idx].lastSyncedAt = nil
        save()
    }

    // MARK: - Sync

    /// Fetches the Navidrome playlist, converts any new tracks, and adds them to the
    /// linked Apple Music playlist. New tracks are injected directly into the queue.
    func syncNow(id: String) async {
        guard let idx = links.firstIndex(where: { $0.id == id }) else { return }
        guard !links[idx].isSyncing, links[idx].isEnabled else { return }

        links[idx].isSyncing = true
        defer {
            if let i = links.firstIndex(where: { $0.id == id }) {
                links[i].isSyncing = false
            }
            save()
        }

        do {
            let tracks = try await navidrome.getPlaylist(id: id)
            let currentIds = Set(tracks.map(\.id))
            let alreadySynced = links[idx].syncedTrackIds
            let playlistName = links[idx].appleMusicPlaylistName

            // Tracks removed from Navidrome playlist since last sync
            let removedIds = alreadySynced.subtracting(currentIds)

            // Tracks new to the Navidrome playlist
            let newTracks = tracks.filter { !alreadySynced.contains($0.id) }

            // --- Handle removals ---
            if !removedIds.isEmpty {
                for removedId in removedIds {
                    if let info = links[idx].syncedTrackInfo[removedId] {
                        try? await appleMusic.removeTrackFromPlaylist(
                            title: info.title,
                            artist: info.artist,
                            playlistName: playlistName
                        )
                    }
                    links[idx].syncedTrackIds.remove(removedId)
                    links[idx].syncedTrackInfo.removeValue(forKey: removedId)
                }
            }

            // --- Handle additions ---
            if !newTracks.isEmpty {
                try await appleMusic.ensurePlaylistExists(name: playlistName)

                // Mark synced before enqueuing so re-triggers don't double-queue
                for track in newTracks {
                    links[idx].syncedTrackIds.insert(track.id)
                    links[idx].syncedTrackInfo[track.id] = SyncedTrackInfo(
                        title: track.title,
                        artist: track.artist ?? ""
                    )
                }

                for track in newTracks {
                    queueVM.enqueue(ConversionJob(track: track, targetPlaylistName: playlistName))
                }
                if !queueVM.isRunning { queueVM.start() }
            }

            links[idx].lastSyncedAt = Date()
            save()

            if !newTracks.isEmpty {
                await notify(playlistName: links[idx].navidromePlaylistName,
                             added: newTracks.count, removed: removedIds.count)
            }
        } catch {
            print("PlaylistSync error for \(links[idx].navidromePlaylistName): \(error)")
        }
    }

    // MARK: - Private

    private func startTimer(for link: PlaylistLink) {
        let interval = TimeInterval(max(link.syncIntervalMinutes, 1) * 60)
        timers[link.id]?.cancel()
        timers[link.id] = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await self?.syncNow(id: link.id)
            }
        }
    }

    private func stopTimer(id: String) {
        timers[id]?.cancel()
        timers.removeValue(forKey: id)
    }

    private func notify(playlistName: String, added: Int, removed: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Playlist Synced — \(playlistName)"
        var parts: [String] = []
        if added > 0  { parts.append("\(added) added") }
        if removed > 0 { parts.append("\(removed) removed") }
        content.body = parts.joined(separator: ", ")
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(links) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([PlaylistLink].self, from: data) else { return }
        links = saved
    }
}
