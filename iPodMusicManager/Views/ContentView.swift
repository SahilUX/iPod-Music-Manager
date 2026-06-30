import SwiftUI
import UserNotifications

enum SidebarItem: String, Hashable {
    case server, playlists, local, history, ipod
}

struct ContentView: View {
    @EnvironmentObject var navidrome: NavidromeClient
    @EnvironmentObject var libraryVM: LibraryViewModel
    @EnvironmentObject var queueVM: QueueViewModel
    @EnvironmentObject var playlistSync: PlaylistSyncService
    @EnvironmentObject var reprocessor: LibraryReprocessor
    @EnvironmentObject var iPodSvc: iPodService

    @State private var selection: SidebarItem? = .server
    @State private var showSettings = false

    var body: some View {
        HStack(spacing: 0) {
            NavigationSplitView {
                SidebarView(selection: $selection)
            } detail: {
                detailView
            }
            .searchable(
                text: $libraryVM.searchText,
                placement: .toolbar,
                prompt: "Search library"
            )
            .onChange(of: selection) { _, newVal in
                // Clear search when leaving Artists
                if newVal != .server { libraryVM.clearSearch() }
            }

            if queueVM.showQueue {
                Divider()
                QueuePanelView()
                    .environmentObject(queueVM)
                    .frame(width: 300)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: queueVM.showQueue)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    queueVM.showQueue.toggle()
                } label: {
                    Label("Queue", systemImage: "list.bullet.rectangle")
                }
                .overlay(alignment: .topTrailing) {
                    if pendingCount > 0 {
                        Text("\(pendingCount)")
                            .font(.caption2).bold()
                            .padding(3)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .offset(x: 6, y: -6)
                    }
                }
            }
        }
        .onAppear {
            navidrome.loadSavedCredentials()
            queueVM.configure(navidrome: navidrome)
            if !navidrome.baseURL.isEmpty {
                Task { try? await navidrome.ping() }
                Task { await libraryVM.loadArtists() }
            }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            iPodSvc.startPolling()
        }
        .dropDestination(for: URL.self) { urls, _ in
            queueVM.enqueueLocalFiles(urls)
            return true
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(navidrome)
                .environmentObject(reprocessor)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings = true
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .server, .none:
            ServerView()
                .environmentObject(libraryVM)
                .environmentObject(queueVM)
                .environmentObject(navidrome)
        case .playlists:
            PlaylistsView()
                .environmentObject(playlistSync)
                .environmentObject(navidrome)
        case .local:
            LocalDropView()
                .environmentObject(queueVM)
        case .history:
            HistoryView()
                .environmentObject(queueVM)
        case .ipod:
            if let device = iPodSvc.connectedDevices.first {
                iPodView(device: device)
                    .environmentObject(iPodSvc)
            } else {
                iPodEmptyView()
            }
        }
    }

    private var pendingCount: Int {
        queueVM.jobs.filter { $0.status == .queued || $0.status == .downloading || $0.status == .converting }.count
    }
}
