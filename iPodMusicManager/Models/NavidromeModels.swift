import Foundation

struct NavidromeArtist: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let albumCount: Int?
    let coverArt: String?
}

struct NavidromeAlbum: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let artist: String?
    let artistId: String?
    let year: Int?
    let coverArt: String?
    let songCount: Int?
    let duration: Int?
}

struct NavidromeTrack: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String?
    let artistId: String?
    let album: String?
    let albumId: String?
    let track: Int?
    let discNumber: Int?
    let year: Int?
    let genre: String?
    let duration: Int?
    let bitRate: Int?
    let size: Int?
    let coverArt: String?
    let suffix: String?

    var durationFormatted: String {
        guard let d = duration else { return "--:--" }
        return String(format: "%d:%02d", d / 60, d % 60)
    }

    var fileSizeMB: String {
        guard let s = size else { return "" }
        return String(format: "%.1f MB", Double(s) / 1_048_576)
    }
}

struct NavidromePlaylist: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let songCount: Int?
    let duration: Int?
    let coverArt: String?
    let comment: String?
}

// MARK: - Subsonic API Response Envelopes

struct SubsonicResponse: Codable {
    let response: SubsonicBody

    enum CodingKeys: String, CodingKey {
        case response = "subsonic-response"
    }
}

struct NavidromeGenre: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let songCount: Int?
    let albumCount: Int?
}

struct SubsonicBody: Codable {
    let status: String
    let version: String
    let type: String?
    let serverVersion: String?
    let artists: ArtistsResponse?
    let artist: ArtistDetailResponse?
    let album: AlbumDetailResponse?
    let albumList2: AlbumList2Response?
    let playlists: PlaylistsResponse?
    let playlist: PlaylistDetailResponse?
    let searchResult3: SearchResult3Response?
    let genres: GenresResponse?
    let songsByGenre: SongsByGenreResponse?
    let error: SubsonicError?
}

struct SubsonicError: Codable {
    let code: Int
    let message: String
}

struct ArtistsResponse: Codable {
    let index: [ArtistIndex]
}

struct ArtistIndex: Codable {
    let name: String
    let artist: [NavidromeArtist]
}

struct ArtistDetailResponse: Codable {
    let id: String
    let name: String
    let album: [NavidromeAlbum]?
}

struct AlbumDetailResponse: Codable {
    let id: String
    let name: String
    let artist: String?
    let year: Int?
    let coverArt: String?
    let song: [NavidromeTrack]?
}

struct PlaylistsResponse: Codable {
    let playlist: [NavidromePlaylist]
}

struct PlaylistDetailResponse: Codable {
    let id: String
    let name: String
    let entry: [NavidromeTrack]?
}

struct SearchResult3Response: Codable {
    let artist: [NavidromeArtist]?
    let album: [NavidromeAlbum]?
    let song: [NavidromeTrack]?
}

struct AlbumList2Response: Codable {
    let album: [NavidromeAlbum]?
}

struct GenresResponse: Codable {
    let genre: [NavidromeGenre]?
}

struct SongsByGenreResponse: Codable {
    let song: [NavidromeTrack]?
}
