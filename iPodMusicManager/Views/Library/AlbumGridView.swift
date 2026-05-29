import SwiftUI

struct AlbumGridView: View {
    let artist: ArtistDetailResponse
    @EnvironmentObject var libraryVM: LibraryViewModel
    @EnvironmentObject var queueVM: QueueViewModel

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(artist.album ?? []) { album in
                    AlbumCard(album: album)
                        .onTapGesture { Task { await libraryVM.selectAlbum(album) } }
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .top) {
            artistHeader
        }
    }

    private var artistHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .font(.title2).fontWeight(.bold)
                let count = artist.album?.count ?? 0
                Text("\(count) album\(count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Add All to Queue") {
                let tracks = (artist.album ?? []).flatMap { _ in [NavidromeTrack]() }
                _ = tracks
                Task {
                    for album in artist.album ?? [] {
                        if let detail = try? await libraryVM.selectedAlbumDetail,
                           detail.id == album.id,
                           let songs = detail.song {
                            queueVM.enqueue(tracks: songs)
                        } else if let detail = try? await NavidromeClient().getAlbum(id: album.id),
                                  let songs = detail.song {
                            queueVM.enqueue(tracks: songs)
                        }
                    }
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

struct AlbumCard: View {
    let album: NavidromeAlbum
    @EnvironmentObject var libraryVM: LibraryViewModel
    @EnvironmentObject var queueVM: QueueViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncCoverArt(url: libraryVM.coverArtURL(id: album.coverArt, size: 200))
                .frame(width: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 3)

            Text(album.name)
                .font(.caption).fontWeight(.medium)
                .lineLimit(1)
            if let year = album.year {
                Text(String(year))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Add Album to Queue") {
                Task {
                    if let detail = try? await NavidromeClient().getAlbum(id: album.id),
                       let songs = detail.song {
                        queueVM.enqueue(tracks: songs)
                    }
                }
            }
        }
    }
}
