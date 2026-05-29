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
    var isSyncing: Bool = false

    init(
        navidromePlaylistId: String,
        navidromePlaylistName: String,
        appleMusicPlaylistName: String,
        autoSync: Bool = true,
        isEnabled: Bool = true,
        syncIntervalMinutes: Int = 60
    ) {
        self.navidromePlaylistId = navidromePlaylistId
        self.navidromePlaylistName = navidromePlaylistName
        self.appleMusicPlaylistName = appleMusicPlaylistName
        self.autoSync = autoSync
        self.isEnabled = isEnabled
        self.syncIntervalMinutes = syncIntervalMinutes
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
        case syncedTrackIds, syncedTrackInfo
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
    }
}
