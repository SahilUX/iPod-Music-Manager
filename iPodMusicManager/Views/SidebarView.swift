import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @EnvironmentObject var navidrome: NavidromeClient
    @EnvironmentObject var queueVM: QueueViewModel

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                Label("Artists", systemImage: "music.mic")
                    .tag(SidebarItem.artists)
                Label("Local Files", systemImage: "folder")
                    .tag(SidebarItem.local)
            }

            Section("Sync") {
                Label("Linked Playlists", systemImage: "arrow.triangle.2.circlepath")
                    .tag(SidebarItem.playlists)
            }

            Section("Activity") {
                Label("History", systemImage: "clock.arrow.circlepath")
                    .tag(SidebarItem.history)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Music Manager")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if queueVM.isRunning {
                    runningBanner
                }
                serverStatusFooter
            }
        }
    }

    private var serverStatusFooter: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(navidrome.isConnected ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
            Text(navidrome.isConnected
                 ? (navidrome.serverVersion.map { "Navidrome \($0)" } ?? "Connected")
                 : "Not connected")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            if !navidrome.isConnected {
                Button("Settings") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .buttonStyle(.borderless)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var runningBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            let active = queueVM.jobs.first { !$0.isFinished && $0.status != .queued }
            Text(active?.track.title ?? "Processing…")
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(8)
    }
}
