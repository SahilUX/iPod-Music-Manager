import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject var playlistSync: PlaylistSyncService
    @EnvironmentObject var navidrome: NavidromeClient
    @State private var selectedId: String?
    @State private var showLinkSheet = false

    var body: some View {
        HSplitView {
            // Left — playlist list
            sidebarList
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)

            // Right — detail
            if let id = selectedId, let link = playlistSync.links.first(where: { $0.id == id }) {
                PlaylistDetailView(link: link)
                    .environmentObject(playlistSync)
                    .environmentObject(navidrome)
                    .id(id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    playlistSync.links.isEmpty ? "No Linked Playlists" : "No Playlist Selected",
                    systemImage: "arrow.triangle.2.circlepath",
                    description: Text(playlistSync.links.isEmpty
                        ? "Link a Navidrome playlist to keep it in sync with Apple Music."
                        : "Select a playlist from the list to manage it.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Link Playlist", systemImage: "plus") { showLinkSheet = true }
                    .disabled(!navidrome.isConnected)
            }
        }
        .sheet(isPresented: $showLinkSheet) {
            LinkPlaylistSheet()
                .environmentObject(playlistSync)
                .environmentObject(navidrome)
        }
        .onChange(of: playlistSync.links.count) { _, _ in
            if selectedId == nil || !playlistSync.links.contains(where: { $0.id == selectedId }) {
                selectedId = playlistSync.links.first?.id
            }
        }
        .onAppear {
            if selectedId == nil { selectedId = playlistSync.links.first?.id }
        }
    }

    private var sidebarList: some View {
        List(selection: $selectedId) {
            ForEach(playlistSync.links) { link in
                PlaylistSidebarRow(link: link)
                    .tag(link.id)
            }
            .onDelete { idxs in
                let toDelete = idxs.map { playlistSync.links[$0].id }
                toDelete.forEach { playlistSync.removeLink(id: $0) }
                if let sel = selectedId, toDelete.contains(sel) {
                    selectedId = playlistSync.links.first?.id
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if playlistSync.links.isEmpty {
                VStack(spacing: 10) {
                    Text("No linked playlists")
                        .foregroundStyle(.secondary).font(.callout)
                    Button("Link Playlist") { showLinkSheet = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!navidrome.isConnected)
                }
            }
        }
    }
}

struct PlaylistSidebarRow: View {
    let link: PlaylistLink

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: link.isEnabled ? "arrow.triangle.2.circlepath" : "pause.circle")
                .foregroundStyle(link.isEnabled && link.autoSync ? .green : .secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(link.navidromePlaylistName)
                    .lineLimit(1)
                    .foregroundStyle(link.isEnabled ? .primary : .secondary)
                Text(link.lastSyncedLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if link.isSyncing {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.vertical, 2)
    }
}
