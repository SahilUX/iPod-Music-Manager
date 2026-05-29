import Foundation
import SwiftUI

@MainActor
final class LibraryViewModel: ObservableObject {
    // Artists
    @Published var artists: [NavidromeArtist] = []
    @Published var selectedArtistDetail: ArtistDetailResponse?
    @Published var selectedAlbumDetail: AlbumDetailResponse?

    // Albums
    @Published var allAlbums: [NavidromeAlbum] = []

    // Genres
    @Published var genres: [NavidromeGenre] = []
    @Published var selectedGenre: NavidromeGenre?
    @Published var genreTracks: [NavidromeTrack] = []

    // Server playlists (browse, not linked sync)
    @Published var serverPlaylists: [NavidromePlaylist] = []
    @Published var selectedServerPlaylist: NavidromePlaylist?
    @Published var serverPlaylistTracks: [NavidromeTrack] = []

    @Published var searchResults: SearchResult3Response?
    @Published var isLoading = false
    @Published var searchText = ""
    @Published var error: String?
    @Published var importedTrackIds: Set<String> = []

    private let client: NavidromeClient
    private var searchTask: Task<Void, Never>?

    init(client: NavidromeClient) {
        self.client = client
    }

    func loadArtists() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            artists = try await client.getArtists()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func selectArtist(_ artist: NavidromeArtist) async {
        selectedAlbumDetail = nil
        isLoading = true
        defer { isLoading = false }
        do {
            selectedArtistDetail = try await client.getArtist(id: artist.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func selectAlbum(_ album: NavidromeAlbum) async {
        isLoading = true
        defer { isLoading = false }
        do {
            selectedAlbumDetail = try await client.getAlbum(id: album.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, !query.isEmpty else {
                searchResults = nil
                return
            }
            do {
                searchResults = try await client.search(query: query)
            } catch {}
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchText = ""
        searchResults = nil
    }

    func coverArtURL(id: String?, size: Int = 64) -> URL? {
        guard let id else { return nil }
        return client.coverArtURL(id: id, size: size)
    }

    func loadAllAlbums(type: AlbumListType = .alphabetical) async {
        isLoading = true; defer { isLoading = false }
        do { allAlbums = try await client.getAlbumList(type: type) }
        catch { self.error = error.localizedDescription }
    }

    func loadGenres() async {
        isLoading = true; defer { isLoading = false }
        do { genres = try await client.getGenres() }
        catch { self.error = error.localizedDescription }
    }

    func selectGenre(_ genre: NavidromeGenre) async {
        selectedGenre = genre
        isLoading = true; defer { isLoading = false }
        do { genreTracks = try await client.getSongsByGenre(genre: genre.name) }
        catch { self.error = error.localizedDescription }
    }

    func loadServerPlaylists() async {
        isLoading = true; defer { isLoading = false }
        do { serverPlaylists = try await client.getPlaylists() }
        catch { self.error = error.localizedDescription }
    }

    func selectServerPlaylist(_ playlist: NavidromePlaylist) async {
        selectedServerPlaylist = playlist
        isLoading = true; defer { isLoading = false }
        do { serverPlaylistTracks = try await client.getPlaylist(id: playlist.id) }
        catch { self.error = error.localizedDescription }
    }

    func markImported(trackId: String) {
        importedTrackIds.insert(trackId)
    }
}
