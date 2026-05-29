import SwiftUI

struct TrackListView: View {
    let album: AlbumDetailResponse
    @EnvironmentObject var libraryVM: LibraryViewModel
    @EnvironmentObject var queueVM: QueueViewModel

    var body: some View {
        List(album.song ?? []) { track in
            TrackRow(track: track)
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .top) {
            albumHeader
        }
    }

    private var albumHeader: some View {
        HStack(spacing: 14) {
            AsyncCoverArt(url: libraryVM.coverArtURL(id: album.coverArt, size: 80))
                .frame(width: 70, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(album.name).font(.headline)
                Text(album.artist ?? "").foregroundStyle(.secondary)
                if let year = album.year { Text(String(year)).font(.caption).foregroundStyle(.secondary) }
            }

            Spacer()

            Button("Add Album to Queue") {
                queueVM.enqueue(tracks: album.song ?? [])
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

struct TrackRow: View {
    let track: NavidromeTrack
    @EnvironmentObject var queueVM: QueueViewModel
    @EnvironmentObject var libraryVM: LibraryViewModel

    private var isImported: Bool { libraryVM.importedTrackIds.contains(track.id) }
    private var isQueued: Bool { queueVM.jobs.contains { $0.track.id == track.id } }

    var body: some View {
        HStack(spacing: 12) {
            Text(track.track.map(String.init) ?? "•")
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).lineLimit(1)
                if let artist = track.artist {
                    Text(artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            Spacer()

            Text(track.durationFormatted)
                .font(.caption).foregroundStyle(.secondary)
                .monospacedDigit()

            statusBadge
        }
        .padding(.vertical, 2)
        .contextMenu {
            if !isImported && !isQueued {
                Button("Add to Queue") { queueVM.enqueue(tracks: [track]) }
            }
            Button("Copy Track Info") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(track.title) — \(track.artist ?? "")", forType: .string)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if isImported {
            badge("In Library", color: .green)
        } else if let job = queueVM.jobs.first(where: { $0.track.id == track.id }) {
            badge(job.statusLabel, color: jobColor(job.status))
        } else {
            Button {
                queueVM.enqueue(tracks: [track])
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
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

    private func jobColor(_ status: JobStatus) -> Color {
        switch status {
        case .queued: return .secondary
        case .downloading: return .orange
        case .converting: return .yellow
        case .importing: return .blue
        case .done, .alreadyInLibrary: return .green
        case .failed: return .red
        case .skipped: return .secondary
        }
    }
}
