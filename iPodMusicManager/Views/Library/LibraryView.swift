import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var libraryVM: LibraryViewModel
    @EnvironmentObject var queueVM: QueueViewModel

    var body: some View {
        Group {
            if let album = libraryVM.selectedAlbumDetail {
                TrackListView(album: album)
            } else if let artist = libraryVM.selectedArtistDetail {
                AlbumGridView(artist: artist)
            } else if !libraryVM.searchText.isEmpty, let results = libraryVM.searchResults {
                SearchResultsView(results: results)
            } else {
                ArtistListView()
            }
        }
        .onChange(of: libraryVM.searchText) { _, _ in libraryVM.scheduleSearch() }
        .navigationTitle(navTitle)
        .toolbar {
            if libraryVM.selectedAlbumDetail != nil {
                ToolbarItem(placement: .navigation) {
                    Button("Back to Artist") {
                        libraryVM.selectedAlbumDetail = nil
                    }
                }
            } else if libraryVM.selectedArtistDetail != nil {
                ToolbarItem(placement: .navigation) {
                    Button("All Artists") {
                        libraryVM.selectedArtistDetail = nil
                    }
                }
            }
        }
    }

    private var navTitle: String {
        if let album = libraryVM.selectedAlbumDetail { return album.name }
        if let artist = libraryVM.selectedArtistDetail { return artist.name }
        return "Artists"
    }
}

struct SearchResultsView: View {
    let results: SearchResult3Response
    @EnvironmentObject var queueVM: QueueViewModel
    @EnvironmentObject var libraryVM: LibraryViewModel

    var body: some View {
        List {
            if let songs = results.song, !songs.isEmpty {
                Section("Tracks (\(songs.count))") {
                    ForEach(songs) { track in
                        TrackRow(track: track)
                    }
                }
            }
            if let albums = results.album, !albums.isEmpty {
                Section("Albums (\(albums.count))") {
                    ForEach(albums) { album in
                        HStack {
                            AsyncCoverArt(url: libraryVM.coverArtURL(id: album.coverArt))
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            VStack(alignment: .leading) {
                                Text(album.name).lineLimit(1)
                                Text(album.artist ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { Task { await libraryVM.selectAlbum(album) } }
                    }
                }
            }
        }
    }
}
