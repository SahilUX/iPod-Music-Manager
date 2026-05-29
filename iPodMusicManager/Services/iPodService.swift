import Foundation
import AppKit

struct ConnectedIPod: Identifiable, Equatable {
    let id: String          // volume path as stable ID
    let name: String
    let volumeURL: URL
    let freeSpaceBytes: Int64
    let capacityBytes: Int64
    var isSyncing: Bool = false

    var freeSpaceLabel: String { formatBytes(freeSpaceBytes) }
    var capacityLabel: String  { formatBytes(capacityBytes) }
    var usedPercent: Double {
        guard capacityBytes > 0 else { return 0 }
        return Double(capacityBytes - freeSpaceBytes) / Double(capacityBytes)
    }

    private func formatBytes(_ b: Int64) -> String {
        let gb = Double(b) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", Double(b) / 1_048_576)
    }
}

@MainActor
final class iPodService: ObservableObject {
    @Published var connectedDevices: [ConnectedIPod] = []
    @Published var lastSyncedAt: Date?

    private var pollTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    func startPolling() {
        // Immediate scan
        Task { await scan() }

        // Watch for volume mount/unmount events
        let mount = NSWorkspace.shared.notificationCenter.addObserver(
            forName: Notification.Name("NSWorkspaceDidMountNotification"), object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in await self?.scan() } }

        let unmount = NSWorkspace.shared.notificationCenter.addObserver(
            forName: Notification.Name("NSWorkspaceDidUnmountNotification"), object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in await self?.scan() } }

        observers = [mount, unmount]

        // Fallback poll every 10s (catches devices that don't fire notifications)
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await self?.scan()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
    }

    func refresh() async { await scan() }

    func eject(device: ConnectedIPod) async {
        connectedDevices.removeAll { $0.id == device.id }
        let result = await runShell("/usr/bin/diskutil", ["eject", device.volumeURL.path])
        if result != 0 {
            // Fallback: NSWorkspace
            try? NSWorkspace.shared.unmountAndEjectDevice(at: device.volumeURL)
        }
    }

    // Sync for disk-mode iPods: open Music.app (it may handle sync on launch)
    // and show the device. Full iTunesDB manipulation is out of scope.
    func sync(device: ConnectedIPod) async {
        guard let idx = connectedDevices.firstIndex(where: { $0.id == device.id }) else { return }
        connectedDevices[idx].isSyncing = true
        defer {
            if let i = connectedDevices.firstIndex(where: { $0.id == device.id }) {
                connectedDevices[i].isSyncing = false
            }
            lastSyncedAt = Date()
        }

        // Try Music.app AppleScript sync first (works if Music manages this device)
        let script = """
        tell application "Music"
            activate
            set ipodSources to every source whose kind is iPod
            if (count of ipodSources) > 0 then
                update (item 1 of ipodSources)
            end if
        end tell
        """
        await runAppleScript(script)
    }

    // MARK: - Private

    private func scan() async {
        let fm = FileManager.default
        let vols = fm.mountedVolumeURLs(includingResourceValuesForKeys: [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsRemovableKey
        ], options: []) ?? []

        var found: [ConnectedIPod] = []
        for url in vols {
            guard (try? url.resourceValues(forKeys: [.volumeIsRemovableKey]).volumeIsRemovable) == true else { continue }
            // Classic iPod: has iPod_Control directory
            let controlDir = url.appendingPathComponent("iPod_Control")
            // Modern iPod/iPhone: has DCIM or iTunes_Control
            let itunesControl = url.appendingPathComponent("iTunes_Control")
            guard fm.fileExists(atPath: controlDir.path) || fm.fileExists(atPath: itunesControl.path) else { continue }

            let res = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            let name = res?.volumeName ?? url.lastPathComponent
            let total = Int64(res?.volumeTotalCapacity ?? 0)
            let free  = Int64(res?.volumeAvailableCapacity ?? 0)

            // Preserve isSyncing state
            let wasSyncing = connectedDevices.first(where: { $0.id == url.path })?.isSyncing ?? false
            found.append(ConnectedIPod(
                id: url.path, name: name, volumeURL: url,
                freeSpaceBytes: free, capacityBytes: total, isSyncing: wasSyncing
            ))
        }
        connectedDevices = found
    }

    @discardableResult
    private func runShell(_ exe: String, _ args: [String]) async -> Int32 {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            p.terminationHandler = { cont.resume(returning: $0.terminationStatus) }
            try? p.run()
        }
    }

    private func runAppleScript(_ script: String) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            p.terminationHandler = { _ in cont.resume() }
            try? p.run()
        }
    }
}
