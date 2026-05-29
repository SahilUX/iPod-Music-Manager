import Foundation
import AppKit

struct ConnectedIPod: Identifiable, Equatable {
    let id: String        // device name as stable ID
    let name: String
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
        let mb = Double(b) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}

@MainActor
final class iPodService: ObservableObject {
    @Published var connectedDevices: [ConnectedIPod] = []
    @Published var lastSyncedAt: Date?

    private var pollTask: Task<Void, Never>?

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        let result = try? await runAppleScriptResult("""
        tell application "Music"
            set out to ""
            set ipodSources to every source whose kind is iPod
            repeat with s in ipodSources
                set sName to name of s
                set sFree to free space of s
                set sCap to capacity of s
                set out to out & sName & "|" & sFree & "|" & sCap & "\\n"
            end repeat
            return out
        end tell
        """)
        let devices = parseDevices(result ?? "")
        // preserve isSyncing flag for existing devices
        connectedDevices = devices.map { new in
            if let existing = connectedDevices.first(where: { $0.id == new.id }) {
                var updated = new
                updated.isSyncing = existing.isSyncing
                return updated
            }
            return new
        }
    }

    func sync(device: ConnectedIPod) async {
        guard let idx = connectedDevices.firstIndex(where: { $0.id == device.id }) else { return }
        connectedDevices[idx].isSyncing = true
        defer {
            if let i = connectedDevices.firstIndex(where: { $0.id == device.id }) {
                connectedDevices[i].isSyncing = false
            }
            lastSyncedAt = Date()
        }
        try? await runAppleScript("""
        tell application "Music"
            activate
            update (first source whose name is "\(escaped(device.name))" and kind is iPod)
        end tell
        """)
    }

    func eject(device: ConnectedIPod) async {
        try? await runAppleScript("""
        tell application "Music"
            eject (first source whose name is "\(escaped(device.name))" and kind is iPod)
        end tell
        """)
        connectedDevices.removeAll { $0.id == device.id }
    }

    // MARK: - Private

    private func parseDevices(_ raw: String) -> [ConnectedIPod] {
        raw.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { line -> ConnectedIPod? in
                let parts = line.components(separatedBy: "|")
                guard parts.count == 3,
                      let free = Int64(parts[1].trimmingCharacters(in: .whitespaces)),
                      let cap  = Int64(parts[2].trimmingCharacters(in: .whitespaces))
                else { return nil }
                let name = parts[0].trimmingCharacters(in: .whitespaces)
                return ConnectedIPod(id: name, name: name, freeSpaceBytes: free, capacityBytes: cap)
            }
    }

    private func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func runAppleScript(_ script: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            p.terminationHandler = { proc in
                proc.terminationStatus == 0
                    ? cont.resume()
                    : cont.resume(throwing: NSError(domain: "iPodService", code: Int(proc.terminationStatus)))
            }
            try? p.run()
        }
    }

    private func runAppleScriptResult(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                cont.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
            try? p.run()
        }
    }
}
