import Foundation

@MainActor
final class NavidromeClient: ObservableObject {
    @Published var isConnected = false
    @Published var serverVersion: String?

    private(set) var baseURL: String = ""
    private(set) var username: String = ""
    private(set) var password: String = ""

    private let clientName = "iPodMusicManager"
    private let apiVersion = "1.16.1"
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func configure(url: String, username: String, password: String) {
        self.baseURL = url.hasSuffix("/") ? String(url.dropLast()) : url
        self.username = username
        self.password = password
        KeychainHelper.save(key: "navidrome_url", value: url)
        KeychainHelper.save(key: "navidrome_user", value: username)
        KeychainHelper.save(key: "navidrome_pass", value: password)
    }

    func loadSavedCredentials() {
        baseURL = KeychainHelper.load(key: "navidrome_url") ?? ""
        username = KeychainHelper.load(key: "navidrome_user") ?? ""
        password = KeychainHelper.load(key: "navidrome_pass") ?? ""
    }

    func ping() async throws {
        let body = try await fetch(endpoint: "ping")
        isConnected = body.status == "ok"
        serverVersion = body.serverVersion ?? body.version
        if let err = body.error { throw NavidromeError.apiError(err.message) }
    }

    func getArtists() async throws -> [NavidromeArtist] {
        let body = try await fetch(endpoint: "getArtists")
        if let err = body.error { throw NavidromeError.apiError(err.message) }
        return body.artists?.index.flatMap(\.artist) ?? []
    }

    func getArtist(id: String) async throws -> ArtistDetailResponse? {
        let body = try await fetch(endpoint: "getArtist", params: ["id": id])
        if let err = body.error { throw NavidromeError.apiError(err.message) }
        return body.artist
    }

    func getAlbum(id: String) async throws -> AlbumDetailResponse? {
        let body = try await fetch(endpoint: "getAlbum", params: ["id": id])
        if let err = body.error { throw NavidromeError.apiError(err.message) }
        return body.album
    }

    func getPlaylists() async throws -> [NavidromePlaylist] {
        let body = try await fetch(endpoint: "getPlaylists")
        if let err = body.error { throw NavidromeError.apiError(err.message) }
        return body.playlists?.playlist ?? []
    }

    func getPlaylist(id: String) async throws -> [NavidromeTrack] {
        let body = try await fetch(endpoint: "getPlaylist", params: ["id": id])
        if let err = body.error { throw NavidromeError.apiError(err.message) }
        return body.playlist?.entry ?? []
    }

    func search(query: String) async throws -> SearchResult3Response? {
        let body = try await fetch(endpoint: "search3", params: [
            "query": query, "artistCount": "10", "albumCount": "20", "songCount": "50"
        ])
        return body.searchResult3
    }

    func downloadTrack(id: String, to destination: URL) async throws {
        guard let url = buildURL(endpoint: "download", params: ["id": id]) else {
            throw NavidromeError.invalidURL
        }
        let (tmpURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NavidromeError.downloadFailed
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tmpURL, to: destination)
    }

    func coverArtURL(id: String, size: Int = 256) -> URL? {
        buildURL(endpoint: "getCoverArt", params: ["id": id, "size": "\(size)"])
    }

    // MARK: - Private

    private func fetch(endpoint: String, params: [String: String] = [:]) async throws -> SubsonicBody {
        guard let url = buildURL(endpoint: endpoint, params: params) else {
            throw NavidromeError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NavidromeError.httpError(http.statusCode)
        }
        do {
            let envelope = try decoder.decode(SubsonicResponse.self, from: data)
            return envelope.response
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            print("[NavidromeClient] Decode failed for \(endpoint): \(error)\nRaw response: \(raw)")
            throw NavidromeError.decodingFailed(String(raw.prefix(300)))
        }
    }

    func buildURL(endpoint: String, params: [String: String] = [:]) -> URL? {
        guard !baseURL.isEmpty else { return nil }
        var components = URLComponents(string: "\(baseURL)/rest/\(endpoint).view")
        var items: [URLQueryItem] = [
            .init(name: "u", value: username),
            .init(name: "p", value: password),
            .init(name: "v", value: apiVersion),
            .init(name: "c", value: clientName),
            .init(name: "f", value: "json")
        ]
        params.forEach { items.append(.init(name: $0.key, value: $0.value)) }
        components?.queryItems = items
        return components?.url
    }
}

enum NavidromeError: LocalizedError {
    case invalidURL, downloadFailed
    case apiError(String)
    case httpError(Int)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL"
        case .downloadFailed: return "Download failed"
        case .apiError(let msg): return msg
        case .httpError(let code): return "Server returned HTTP \(code)"
        case .decodingFailed(let raw): return "Unexpected response: \(raw)"
        }
    }
}

// MARK: - Simple Keychain wrapper

enum KeychainHelper {
    static func save(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
