import Foundation
import SwiftUI

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var artists: [NavidromeArtist] = []
    @Published var selectedArtistDetail: ArtistDetailResponse?
    @Published var selectedAlbumDetail: AlbumDetailResponse?
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

    func markImported(trackId: String) {
        importedTrackIds.insert(trackId)
    }
}
