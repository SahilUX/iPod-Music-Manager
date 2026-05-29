import SwiftUI

struct iPodView: View {
    let device: ConnectedIPod
    @EnvironmentObject var iPodService: iPodService

    var body: some View {
        VStack(spacing: 24) {
            deviceCard
            actionsCard
            Spacer()
        }
        .padding(24)
        .navigationTitle(device.name)
    }

    private var deviceCard: some View {
        HStack(spacing: 20) {
            Image(systemName: "ipodclassic")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .frame(width: 64)

            VStack(alignment: .leading, spacing: 6) {
                Text(device.name)
                    .font(.title3).fontWeight(.semibold)

                // Storage bar
                VStack(alignment: .leading, spacing: 3) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.2))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(storageColor)
                                .frame(width: geo.size.width * device.usedPercent)
                        }
                    }
                    .frame(height: 6)

                    Text("\(device.freeSpaceLabel) free of \(device.capacityLabel)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var actionsCard: some View {
        HStack(spacing: 12) {
            // Sync
            Button {
                Task { await iPodService.sync(device: device) }
            } label: {
                if device.isSyncing {
                    Label("Syncing…", systemImage: "arrow.triangle.2.circlepath")
                } else {
                    Label("Sync with Music", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(device.isSyncing)

            // Eject
            Button {
                Task { await iPodService.eject(device: device) }
            } label: {
                Label("Eject", systemImage: "eject")
            }
            .buttonStyle(.bordered)
            .disabled(device.isSyncing)

            Spacer()

            if let synced = iPodService.lastSyncedAt {
                let fmt = RelativeDateTimeFormatter()
                Text("Last synced \(fmt.localizedString(for: synced, relativeTo: Date()))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var storageColor: Color {
        device.usedPercent > 0.9 ? .red : device.usedPercent > 0.75 ? .orange : .accentColor
    }
}

struct iPodEmptyView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "ipodclassic")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No iPod Connected")
                .font(.title3).fontWeight(.semibold)
            Text("Connect your iPod via USB and it will appear here automatically.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
