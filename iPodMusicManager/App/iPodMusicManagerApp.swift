import SwiftUI

extension Notification.Name {
    static let openSettings = Notification.Name("com.sahil.ipm.openSettings")
}

@main
struct iPodMusicManagerApp: App {
    @StateObject private var navidrome: NavidromeClient
    @StateObject private var queueVM: QueueViewModel
    @StateObject private var libraryVM: LibraryViewModel
    @StateObject private var playlistSync: PlaylistSyncService
    @StateObject private var iPodSvc = iPodService()

    init() {
        let nav = NavidromeClient()
        let queue = QueueViewModel()
        let pipeline = ConversionPipeline()
        let appleMusic = AppleMusicService()
        _navidrome = StateObject(wrappedValue: nav)
        _queueVM = StateObject(wrappedValue: queue)
        _libraryVM = StateObject(wrappedValue: LibraryViewModel(client: nav))
        _playlistSync = StateObject(wrappedValue: PlaylistSyncService(
            navidrome: nav, pipeline: pipeline, appleMusic: appleMusic, queueVM: queue
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(navidrome)
                .environmentObject(queueVM)
                .environmentObject(libraryVM)
                .environmentObject(playlistSync)
                .environmentObject(iPodSvc)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    // Restore Dock icon preference — deferred until NSApp is ready
                    let saved = UserDefaults.standard.string(forKey: "preferredAppIcon")
                        ?? AppIconChoice.waveform.rawValue
                    if let choice = AppIconChoice(rawValue: saved), let img = choice.nsImage {
                        NSApp.applicationIconImage = img
                    }
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
