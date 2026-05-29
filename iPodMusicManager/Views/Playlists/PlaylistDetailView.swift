import SwiftUI

struct PlaylistDetailView: View {
    let link: PlaylistLink
    @EnvironmentObject var playlistSync: PlaylistSyncService
    @EnvironmentObject var navidrome: NavidromeClient

    @State private var appleMusicName: String
    @State private var autoSync: Bool
    @State private var isEnabled: Bool
    @State private var syncInterval: Int
    @State private var isDirty = false
    @State private var showResetConfirm = false
    @State private var showDeleteConfirm = false

    private let intervalOptions = [15, 30, 60, 360, 1440]

    init(link: PlaylistLink) {
        self.link = link
        _appleMusicName = State(initialValue: link.appleMusicPlaylistName)
        _autoSync      = State(initialValue: link.autoSync)
        _isEnabled     = State(initialValue: link.isEnabled)
        _syncInterval  = State(initialValue: link.syncIntervalMinutes)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerCard
                settingsCard
                syncStatusCard
                dangerCard
            }
            .padding(24)
        }
        .navigationTitle(link.navidromePlaylistName)
        .toolbar { saveToolbar }
        .onAppear { loadState() }
        .onChange(of: link) { _, _ in loadState() }
    }

    // MARK: - Cards

    private var headerCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .frame(width: 56, height: 56)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(link.navidromePlaylistName)
                        .font(.title3).fontWeight(.semibold)
                    statusBadge
                }
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(link.appleMusicPlaylistName)
                        .foregroundStyle(.secondary)
                }
                Text("\(link.syncedCount) track\(link.syncedCount == 1 ? "" : "s") synced")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            Spacer()

            if link.isSyncing {
                VStack(spacing: 6) {
                    ProgressView().controlSize(.regular)
                    Text("Syncing…").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task { await playlistSync.syncNow(id: link.id) }
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!link.isEnabled || !navidrome.isConnected)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Settings")
            VStack(spacing: 0) {
                settingsRow {
                    Toggle("Enabled", isOn: $isEnabled)
                        .onChange(of: isEnabled) { _, _ in isDirty = true }
                }
                Divider().padding(.leading, 12)
                settingsRow {
                    HStack {
                        Text("Navidrome Playlist").foregroundStyle(.secondary)
                        Spacer()
                        Text(link.navidromePlaylistName).foregroundStyle(.secondary)
                    }
                }
                Divider().padding(.leading, 12)
                settingsRow {
                    HStack {
                        Text("Apple Music Playlist")
                        Spacer()
                        TextField("Name", text: $appleMusicName)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 200)
                            .onChange(of: appleMusicName) { _, _ in isDirty = true }
                    }
                }
                Divider().padding(.leading, 12)
                settingsRow {
                    Toggle("Auto-sync", isOn: $autoSync)
                        .onChange(of: autoSync) { _, _ in isDirty = true }
                }
                if autoSync {
                    Divider().padding(.leading, 12)
                    settingsRow {
                        HStack {
                            Text("Check every")
                            Spacer()
                            Picker("", selection: $syncInterval) {
                                ForEach(intervalOptions, id: \.self) { mins in
                                    Text(intervalLabel(mins)).tag(mins)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 100)
                            .onChange(of: syncInterval) { _, _ in isDirty = true }
                        }
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func settingsRow(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
    }

    private var syncStatusCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Sync Status")
            VStack(spacing: 12) {
                statusRow("Last synced", value: link.lastSyncedAt.map { fullDate($0) } ?? "Never")
                Divider()
                statusRow("Tracks synced", value: "\(link.syncedCount)")
                Divider()
                statusRow("Apple Music playlist", value: link.appleMusicPlaylistName)
                Divider()
                statusRow("Auto-sync", value: link.autoSync ? "Every \(intervalLabel(link.syncIntervalMinutes))" : "Off")
            }
            .padding(14)
            .background(.quaternary.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var dangerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Actions")
            VStack(spacing: 10) {
                Button {
                    showResetConfirm = true
                } label: {
                    Label("Reset Sync State", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .confirmationDialog(
                    "Reset sync state for \"\(link.navidromePlaylistName)\"?",
                    isPresented: $showResetConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Reset", role: .destructive) {
                        playlistSync.resetSync(id: link.id)
                    }
                } message: {
                    Text("All \(link.syncedCount) tracks will be marked as unsynced and re-imported on the next sync.")
                }

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Remove Link", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .confirmationDialog(
                    "Remove \"\(link.navidromePlaylistName)\"?",
                    isPresented: $showDeleteConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Remove Link", role: .destructive) {
                        playlistSync.removeLink(id: link.id)
                    }
                } message: {
                    Text("The Apple Music playlist \"\(link.appleMusicPlaylistName)\" will not be deleted.")
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var saveToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Save") { saveChanges() }
                .disabled(!isDirty)
        }
    }

    // MARK: - Helpers

    private func loadState() {
        appleMusicName = link.appleMusicPlaylistName
        autoSync = link.autoSync
        isEnabled = link.isEnabled
        syncInterval = link.syncIntervalMinutes
        isDirty = false
    }

    private func saveChanges() {
        var updated = link
        updated.appleMusicPlaylistName = appleMusicName
        updated.autoSync = autoSync
        updated.isEnabled = isEnabled
        updated.syncIntervalMinutes = syncInterval
        playlistSync.updateLink(updated)
        isDirty = false
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline).fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
    }

    private func statusRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(.primary)
        }
        .font(.callout)
    }

    private var statusBadge: some View {
        Group {
            if !link.isEnabled {
                badge("Paused", color: .secondary)
            } else if link.isSyncing {
                badge("Syncing", color: .blue)
            } else if link.autoSync {
                badge("Auto", color: .green)
            } else {
                badge("Manual", color: .secondary)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func intervalLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hrs = minutes / 60
        return "\(hrs) hr\(hrs == 1 ? "" : "s")"
    }

    private func fullDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}
