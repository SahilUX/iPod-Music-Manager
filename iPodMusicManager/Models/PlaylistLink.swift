import Foundation

struct SyncedTrackInfo: Codable, Hashable {
    let title: String
    let artist: String
}

struct PlaylistLink: Codable, Identifiable, Hashable {
    var id: String { navidromePlaylistId }
    let navidromePlaylistId: String
    var navidromePlaylistName: String
    var appleMusicPlaylistName: String
    var autoSync: Bool
    var isEnabled: Bool
    var syncIntervalMinutes: Int
    var lastSyncedAt: Date?
    var syncedTrackIds: Set<String>
    var syncedTrackInfo: [String: SyncedTrackInfo]  // trackId → title/artist for removal
    /// When true, tracks are imported into the Apple Music library only — no Apple Music
    /// playlist is created or maintained for this link.
    var libraryOnly: Bool
    var isSyncing: Bool = false

    init(
        navidromePlaylistId: String,
        navidromePlaylistName: String,
        appleMusicPlaylistName: String,
        autoSync: Bool = true,
        isEnabled: Bool = true,
        syncIntervalMinutes: Int = 60,
        libraryOnly: Bool = false
    ) {
        self.navidromePlaylistId = navidromePlaylistId
        self.navidromePlaylistName = navidromePlaylistName
        self.appleMusicPlaylistName = appleMusicPlaylistName
        self.autoSync = autoSync
        self.isEnabled = isEnabled
        self.syncIntervalMinutes = syncIntervalMinutes
        self.libraryOnly = libraryOnly
        self.syncedTrackIds = []
        self.syncedTrackInfo = [:]
    }

    var syncedCount: Int { syncedTrackIds.count }

    var lastSyncedLabel: String {
        guard let date = lastSyncedAt else { return "Never synced" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Synced \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    // MARK: - Codable with backward-compat defaults

    enum CodingKeys: String, CodingKey {
        case navidromePlaylistId, navidromePlaylistName, appleMusicPlaylistName
        case autoSync, isEnabled, syncIntervalMinutes, lastSyncedAt
        case syncedTrackIds, syncedTrackInfo, libraryOnly
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        navidromePlaylistId    = try c.decode(String.self,           forKey: .navidromePlaylistId)
        navidromePlaylistName  = try c.decode(String.self,           forKey: .navidromePlaylistName)
        appleMusicPlaylistName = try c.decode(String.self,           forKey: .appleMusicPlaylistName)
        autoSync               = try c.decode(Bool.self,             forKey: .autoSync)
        isEnabled              = try c.decodeIfPresent(Bool.self,    forKey: .isEnabled) ?? true
        syncIntervalMinutes    = try c.decode(Int.self,              forKey: .syncIntervalMinutes)
        lastSyncedAt           = try c.decodeIfPresent(Date.self,    forKey: .lastSyncedAt)
        syncedTrackIds         = try c.decode(Set<String>.self,      forKey: .syncedTrackIds)
        syncedTrackInfo        = try c.decodeIfPresent([String: SyncedTrackInfo].self, forKey: .syncedTrackInfo) ?? [:]
        libraryOnly            = try c.decodeIfPresent(Bool.self,    forKey: .libraryOnly) ?? false
    }
}
