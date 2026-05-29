import SwiftUI

enum ServerBrowseMode: String, CaseIterable {
    case artists   = "Artists"
    case albums    = "Albums"
    case songs     = "Songs"
    case playlists = "Playlists"
    case genres    = "Genres"
    case recent    = "Recent"

    var icon: String {
        switch self {
        case .artists:   return "music.mic"
        case .albums:    return "square.grid.2x2"
        case .songs:     return "music.note"
        case .playlists: return "music.note.list"
        case .genres:    return "tag"
        case .recent:    return "clock"
        }
    }
}

struct ServerView: View {
    @EnvironmentObject var libraryVM: LibraryViewModel
    @EnvironmentObject var queueVM: QueueViewModel
    @EnvironmentObject var navidrome: NavidromeClient
    @State private var mode: ServerBrowseMode = .artists

    var body: some View {
        VStack(spacing: 0) {
            // Browse mode picker
            HStack(spacing: 4) {
                ForEach(ServerBrowseMode.allCases, id: \.self) { m in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { mode = m }
                    } label: {
                        Label(m.rawValue, systemImage: m.icon)
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(mode == m ? Color.accentColor.opacity(0.15) : Color.clear)
                            .foregroundStyle(mode == m ? Color.accentColor : Color.secondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Content
            Group {
                switch mode {
                case .artists:   artistsContent
                case .albums:    albumsContent
                case .songs:     songsContent
                case .playlists: playlistsContent
                case .genres:    genresContent
                case .recent:    recentContent
                }
            }
        }
        .onChange(of: mode) { _, newMode in
            Task { await loadIfNeeded(newMode) }
        }
        .onAppear {
            Task { await loadIfNeeded(mode) }
        }
    }

    // MARK: - Artists

    private var artistsContent: some View {
        Group {
            if let album = libraryVM.selectedAlbumDetail {
                TrackListView(album: album)
                    .toolbar { backToArtistToolbar }
            } else if let artist = libraryVM.selectedArtistDetail {
                AlbumGridView(artist: artist)
                    .toolbar { backToArtistsToolbar }
            } else if !libraryVM.searchText.isEmpty, let results = libraryVM.searchResults {
                SearchResultsView(results: results)
            } else {
                ArtistListView()
            }
        }
        .onChange(of: libraryVM.searchText) { _, _ in libraryVM.scheduleSearch() }
    }

    @ToolbarContentBuilder
    private var backToArtistToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button("Back") { libraryVM.selectedAlbumDetail = nil }
        }
    }

    @ToolbarContentBuilder
    private var backToArtistsToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button("All Artists") { libraryVM.selectedArtistDetail = nil }
        }
    }

    // MARK: - Songs

    private var songsContent: some View {
        AllSongsListView(songs: libraryVM.allSongs)
    }

    // MARK: - Albums

    private var albumsContent: some View {
        Group {
            if let album = libraryVM.selectedAlbumDetail {
                TrackListView(album: album)
            } else {
                AllAlbumsGridView(albums: libraryVM.allAlbums)
            }
        }
    }

    // MARK: - Playlists

    private var playlistsContent: some View {
        Group {
            if let playlist = libraryVM.selectedServerPlaylist {
                ServerPlaylistTrackList(playlist: playlist, tracks: libraryVM.serverPlaylistTracks)
            } else {
                ServerPlaylistListView(playlists: libraryVM.serverPlaylists)
            }
        }
    }

    // MARK: - Genres

    private var genresContent: some View {
        Group {
            if let genre = libraryVM.selectedGenre {
                GenreTrackList(genre: genre, tracks: libraryVM.genreTracks)
            } else {
                GenreListView(genres: libraryVM.genres)
            }
        }
    }

    // MARK: - Recent

    private var recentContent: some View {
        Group {
            if let album = libraryVM.selectedAlbumDetail {
                TrackListView(album: album)
            } else {
                AllAlbumsGridView(albums: libraryVM.allAlbums, title: "Recently Added")
            }
        }
    }

    // MARK: - Load

    private func loadIfNeeded(_ m: ServerBrowseMode) async {
        guard navidrome.isConnected else { return }
        switch m {
        case .artists:
            if libraryVM.artists.isEmpty { await libraryVM.loadArtists() }
        case .songs:
            await libraryVM.loadAllSongs()
        case .albums:
            libraryVM.selectedAlbumDetail = nil
            await libraryVM.loadAllAlbums(type: .alphabetical)
        case .playlists:
            libraryVM.selectedServerPlaylist = nil
            await libraryVM.loadServerPlaylists()
        case .genres:
            libraryVM.selectedGenre = nil
            if libraryVM.genres.isEmpty { await libraryVM.loadGenres() }
        case .recent:
            libraryVM.selectedAlbumDetail = nil
            await libraryVM.loadAllAlbums(type: .newest)
        }
    }
}

// MARK: - All Songs List

struct AllSongsListView: View {
    let songs: [NavidromeTrack]
    @EnvironmentObject var queueVM: QueueViewModel
    @EnvironmentObject var libraryVM: LibraryViewModel
    @State private var sortOrder = SongSort.title

    enum SongSort: String, CaseIterable {
        case title = "Title", artist = "Artist", album = "Album", duration = "Duration"
    }

    private func sortButton(_ s: SongSort) -> some View {
        let active = sortOrder == s
        return Button(s.rawValue) { sortOrder = s }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(active ? Color.accentColor : Color.secondary)
            .fontWeight(active ? .semibold : .regular)
    }

    private var sorted: [NavidromeTrack] {
        switch sortOrder {
        case .title:    return songs.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .artist:   return songs.sorted { ($0.artist ?? "").localizedCompare($1.artist ?? "") == .orderedAscending }
        case .album:    return songs.sorted { ($0.album ?? "").localizedCompare($1.album ?? "") == .orderedAscending }
        case .duration: return songs.sorted { ($0.duration ?? 0) < ($1.duration ?? 0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sort bar
            HStack(spacing: 4) {
                Text("Sort:")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(SongSort.allCases, id: \.self) { s in
                    sortButton(s)
                }
                Spacer()
                if !songs.isEmpty {
                    Text("\(songs.count) tracks")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Add All") { queueVM.enqueue(tracks: songs) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            if songs.isEmpty {
                ProgressView("Loading songs…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sorted) { track in
                    TrackRow(track: track)
                }
                .listStyle(.inset)
            }
        }
    }
}

// MARK: - All Albums Grid

struct AllAlbumsGridView: View {
    let albums: [NavidromeAlbum]
    var title: String = "Albums"
    @EnvironmentObject var libraryVM: LibraryViewModel
    @EnvironmentObject var queueVM: QueueViewModel

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)]

    var body: some View {
        ScrollView {
            if albums.isEmpty {
                ProgressView("Loading \(title.lowercased())…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(albums) { album in
                        AlbumCard(album: album)
                            .onTapGesture { Task { await libraryVM.selectAlbum(album) } }
                    }
                }
                .padding()
            }
        }
        .navigationTitle(title)
    }
}

// MARK: - Server Playlists

struct ServerPlaylistListView: View {
    let playlists: [NavidromePlaylist]
    @EnvironmentObject var libraryVM: LibraryViewModel

    var body: some View {
        List(playlists) { playlist in
            HStack(spacing: 12) {
                AsyncCoverArt(url: libraryVM.coverArtURL(id: playlist.coverArt, size: 48))
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name).fontWeight(.medium)
                    if let count = playlist.songCount {
                        Text("\(count) tracks").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption)
            }
            .contentShape(Rectangle())
            .onTapGesture { Task { await libraryVM.selectServerPlaylist(playlist) } }
        }
        .listStyle(.inset)
        .navigationTitle("Playlists")
        .overlay {
            if playlists.isEmpty {
                ContentUnavailableView("No Playlists", systemImage: "music.note.list",
                    description: Text("Create playlists in Navidrome to see them here."))
            }
        }
    }
}

struct ServerPlaylistTrackList: View {
    let playlist: NavidromePlaylist
    let tracks: [NavidromeTrack]
    @EnvironmentObject var libraryVM: LibraryViewModel
    @EnvironmentObject var queueVM: QueueViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("All Playlists") { libraryVM.selectedServerPlaylist = nil }
                    .buttonStyle(.borderless)
                Spacer()
                Button("Add All to Queue") { queueVM.enqueue(tracks: tracks) }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal).padding(.vertical, 8)
            .background(.bar)
            Divider()
            List(tracks) { track in
                TrackRow(track: track)
            }
            .listStyle(.inset)
        }
        .navigationTitle(playlist.name)
    }
}

// MARK: - Genres

struct GenreListView: View {
    let genres: [NavidromeGenre]
    @EnvironmentObject var libraryVM: LibraryViewModel

    var body: some View {
        List(genres) { genre in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(genre.name).fontWeight(.medium)
                    HStack(spacing: 8) {
                        if let a = genre.albumCount { Text("\(a) albums").font(.caption).foregroundStyle(.secondary) }
                        if let s = genre.songCount  { Text("\(s) tracks").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption)
            }
            .contentShape(Rectangle())
            .onTapGesture { Task { await libraryVM.selectGenre(genre) } }
        }
        .listStyle(.inset)
        .navigationTitle("Genres")
        .overlay {
            if genres.isEmpty {
                ProgressView("Loading genres…").padding(.top, 80)
            }
        }
    }
}

struct GenreTrackList: View {
    let genre: NavidromeGenre
    let tracks: [NavidromeTrack]
    @EnvironmentObject var libraryVM: LibraryViewModel
    @EnvironmentObject var queueVM: QueueViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("All Genres") { libraryVM.selectedGenre = nil }
                    .buttonStyle(.borderless)
                Spacer()
                Button("Add All to Queue") { queueVM.enqueue(tracks: tracks) }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal).padding(.vertical, 8)
            .background(.bar)
            Divider()
            List(tracks) { track in
                TrackRow(track: track)
            }
            .listStyle(.inset)
        }
        .navigationTitle(genre.name)
    }
}
