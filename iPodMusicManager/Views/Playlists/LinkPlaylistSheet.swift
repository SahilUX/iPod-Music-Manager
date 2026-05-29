import SwiftUI

struct LinkPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var playlistSync: PlaylistSyncService
    @EnvironmentObject var navidrome: NavidromeClient

    @State private var navidromePlaylists: [NavidromePlaylist] = []
    @State private var selectedPlaylist: NavidromePlaylist?
    @State private var appleMusicName = ""
    @State private var autoSync = true
    @State private var syncInterval = 60
    @State private var isLoading = true
    @State private var error: String?

    private let intervalOptions = [15, 30, 60, 360, 1440]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Link a Playlist")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            Form {
                Section("Navidrome Playlist") {
                    if isLoading {
                        ProgressView("Loading playlists…")
                    } else if let err = error {
                        Text(err).foregroundStyle(.red)
                    } else {
                        Picker("Select playlist", selection: $selectedPlaylist) {
                            Text("Choose…").tag(Optional<NavidromePlaylist>(nil))
                            ForEach(navidromePlaylists) { pl in
                                Text(pl.name).tag(Optional(pl))
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedPlaylist) { _, pl in
                            if let pl, appleMusicName.isEmpty {
                                appleMusicName = pl.name
                            }
                        }
                        if let pl = selectedPlaylist {
                            Text("\(pl.songCount ?? 0) tracks")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Apple Music Playlist") {
                    TextField("Playlist name", text: $appleMusicName)
                    Text("This playlist will be created in Apple Music if it doesn't exist.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Auto Sync") {
                    Toggle("Automatically sync on schedule", isOn: $autoSync)
                    if autoSync {
                        Picker("Check every", selection: $syncInterval) {
                            ForEach(intervalOptions, id: \.self) { mins in
                                Text(intervalLabel(mins)).tag(mins)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    Text("New tracks added to the Navidrome playlist will be automatically converted and added to Apple Music.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Link Playlist") {
                    guard let pl = selectedPlaylist, !appleMusicName.isEmpty else { return }
                    let link = PlaylistLink(
                        navidromePlaylistId: pl.id,
                        navidromePlaylistName: pl.name,
                        appleMusicPlaylistName: appleMusicName,
                        autoSync: autoSync,
                        syncIntervalMinutes: syncInterval
                    )
                    playlistSync.addLink(link)
                    Task { await playlistSync.syncNow(id: link.id) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPlaylist == nil || appleMusicName.isEmpty)
            }
            .padding()
        }
        .frame(width: 440)
        .task { await loadPlaylists() }
    }

    private func loadPlaylists() async {
        isLoading = true
        defer { isLoading = false }
        do {
            navidromePlaylists = try await navidrome.getPlaylists()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func intervalLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) minutes" }
        let hrs = minutes / 60
        return "\(hrs) hour\(hrs == 1 ? "" : "s")"
    }
}
