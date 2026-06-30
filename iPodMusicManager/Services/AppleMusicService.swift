import Foundation

/// A snapshot of an Apple Music library track's current encoding/art state.
struct LibraryTrackInfo {
    let databaseID: Int
    let title: String
    let artist: String
    let kind: String        // e.g. "AAC audio file", "Apple Lossless audio file", "MPEG audio file"
    let bitRate: Int        // kbps (0 if unknown)
    let hasArtwork: Bool
}

final class AppleMusicService {

    /// Adds a file to the library and returns the new track's database ID — or nil if
    /// Apple Music silently ignored it (e.g. FLAC). The ID lets callers reference the
    /// exact track afterward without relying on (often-mismatched) metadata matching.
    @discardableResult
    func importTrack(m4aURL: URL) async throws -> Int? {
        // No `activate` — adding a track shouldn't steal focus by bringing Music forward.
        let result = try await osascriptResult("""
        tell application "Music"
            try
                set newTrack to (add POSIX file "\(escaped(m4aURL.path))")
                return (database ID of newTrack) as text
            on error
                return ""
            end try
        end tell
        """)
        return Int(result.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func ensurePlaylistExists(name: String) async throws {
        try await osascript("""
        tell application "Music"
            if not (exists user playlist "\(escaped(name))") then
                make new user playlist with properties {name:"\(escaped(name))"}
            end if
        end tell
        """)
    }

    /// Adds the library track with `databaseID` to a playlist, creating the playlist if
    /// needed and skipping if the track is already in it — so a track appearing in several
    /// playlists is added to each without ever duplicating it.
    func addTrackToPlaylistByID(databaseID: Int, playlistName: String) async throws {
        try await osascript("""
        tell application "Music"
            if not (exists user playlist "\(escaped(playlistName))") then
                make new user playlist with properties {name:"\(escaped(playlistName))"}
            end if
            set thePlaylist to user playlist "\(escaped(playlistName))"
            set libMatches to (tracks of library playlist 1 whose database ID is \(databaseID))
            if (count of libMatches) > 0 then
                if (count of (tracks of thePlaylist whose database ID is \(databaseID))) = 0 then
                    duplicate item 1 of libMatches to thePlaylist
                end if
            end if
        end tell
        """)
    }

    /// Removes a track from a user playlist using tolerant matching: it reads the
    /// playlist's tracks, matches by normalized title + primary artist (so multi-artist
    /// tracks aren't missed), and deletes the matching entries by database ID. Only the
    /// playlist entry is removed — the library track is untouched.
    func removeTrackFromPlaylist(title: String, artist: String, playlistName: String) async {
        guard let entries = await playlistTrackIdentities(playlistName: playlistName) else { return }
        let targetKey = TrackMatch.key(title: title, artist: artist)
        let ids = entries
            .filter { TrackMatch.key(title: $0.title, artist: $0.artist) == targetKey }
            .map(\.id)
        for id in ids {
            try? await deletePlaylistTrackByID(databaseID: id, playlistName: playlistName)
        }
    }

    /// (databaseID, title, artist) for each track in a user playlist. Returns [] if the
    /// playlist doesn't exist, or nil if the read failed (distinguished by the "OK" marker).
    func playlistTrackIdentities(playlistName: String) async -> [(id: Int, title: String, artist: String)]? {
        let result = try? await osascriptResult("""
        tell application "Music"
            if not (exists user playlist "\(escaped(playlistName))") then return "OK"
            set fs to (ASCII character 30)
            set out to "OK" & linefeed
            repeat with t in (tracks of user playlist "\(escaped(playlistName))")
                set out to out & (database ID of t) & fs & (name of t) & fs & (artist of t) & linefeed
            end repeat
            return out
        end tell
        """)
        var lines = (result ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let header = lines.first, header.trimmingCharacters(in: .whitespacesAndNewlines) == "OK" else {
            return nil
        }
        lines.removeFirst()
        let sep = Character(UnicodeScalar(30))
        return lines.compactMap { line in
            guard !line.isEmpty else { return nil }
            let f = line.split(separator: sep, omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 3, let id = Int(f[0]) else { return nil }
            return (id: id, title: f[1], artist: f[2])
        }
    }

    /// Deletes the playlist entry with `databaseID` from a user playlist (library untouched).
    func deletePlaylistTrackByID(databaseID: Int, playlistName: String) async throws {
        try await osascript("""
        tell application "Music"
            if exists user playlist "\(escaped(playlistName))" then
                set thePlaylist to user playlist "\(escaped(playlistName))"
                repeat with t in (tracks of thePlaylist whose database ID is \(databaseID))
                    delete t
                end repeat
            end if
        end tell
        """)
    }

    /// Database IDs of library tracks matching (title, artist). Captured before a
    /// replace so the *old* track can be deleted by ID without touching the new one.
    func trackDatabaseIDs(title: String, artist: String) async -> [Int] {
        let result = try? await osascriptResult("""
        tell application "Music"
            set out to ""
            repeat with t in (tracks of library playlist 1 whose name is "\(escaped(title))" and artist is "\(escaped(artist))")
                set out to out & (database ID of t) & linefeed
            end repeat
            return out
        end tell
        """)
        return (result ?? "")
            .split(separator: "\n")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Deletes a single library track by its database ID.
    func deleteTrackByDatabaseID(_ databaseID: Int) async throws {
        try await osascript("""
        tell application "Music"
            set matches to (tracks of library playlist 1 whose database ID is \(databaseID))
            repeat with t in matches
                delete t
            end repeat
        end tell
        """)
    }

    /// Names of user playlists that currently contain the track — captured before a
    /// replace so membership can be restored afterward.
    func playlistsContaining(title: String, artist: String) async -> [String] {
        let result = try? await osascriptResult("""
        tell application "Music"
            set out to ""
            repeat with p in user playlists
                try
                    if (count of (tracks of p whose name is "\(escaped(title))" and artist is "\(escaped(artist))")) > 0 then
                        set out to out & (name of p) & linefeed
                    end if
                end try
            end repeat
            return out
        end tell
        """)
        return (result ?? "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Sets cover art on an existing library track from raw image data.
    func setArtwork(title: String, artist: String, imageData: Data) async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).artwork")
        try imageData.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await osascript("""
        tell application "Music"
            set matches to (tracks of library playlist 1 whose name is "\(escaped(title))" and artist is "\(escaped(artist))")
            if (count of matches) > 0 then
                set t to item 1 of matches
                set data of artwork 1 of t to (read (POSIX file "\(escaped(tmp.path))") as picture)
            end if
        end tell
        """)
    }

    /// Removes any cover art from an existing library track.
    func removeArtwork(title: String, artist: String) async throws {
        try await osascript("""
        tell application "Music"
            set matches to (tracks of library playlist 1 whose name is "\(escaped(title))" and artist is "\(escaped(artist))")
            if (count of matches) > 0 then
                set t to item 1 of matches
                if (count of artworks of t) > 0 then delete artwork 1 of t
            end if
        end tell
        """)
    }

    /// Reads every library track's title/artist/kind/bitrate/artwork state in one pass.
    /// Fields are separated by ASCII 30 and records by newline so titles/artists
    /// containing tabs or other punctuation parse cleanly. Returns nil if the library
    /// couldn't be read (vs. an empty array for a genuinely empty library) — the leading
    /// "OK" marker tells the two apart so callers never mistake a read error for "empty".
    func allLibraryTracks() async -> [LibraryTrackInfo]? {
        let result = try? await osascriptResult("""
        tell application "Music"
            set fs to (ASCII character 30)
            set out to "OK" & linefeed
            repeat with t in (every track of library playlist 1)
                set hasArt to "0"
                try
                    if (count of artworks of t) > 0 then set hasArt to "1"
                end try
                set br to 0
                try
                    set br to (bit rate of t)
                end try
                set out to out & (database ID of t) & fs & (name of t) & fs & (artist of t) & fs & (kind of t) & fs & (br as text) & fs & hasArt & linefeed
            end repeat
            return out
        end tell
        """)
        var lines = (result ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let header = lines.first, header.trimmingCharacters(in: .whitespacesAndNewlines) == "OK" else {
            return nil  // script didn't run to completion
        }
        lines.removeFirst()
        let sep = Character(UnicodeScalar(30))
        return lines.compactMap { line in
            guard !line.isEmpty else { return nil }
            let f = line.split(separator: sep, omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 6 else { return nil }
            return LibraryTrackInfo(
                databaseID: Int(f[0]) ?? 0, title: f[1], artist: f[2], kind: f[3],
                bitRate: Int(f[4]) ?? 0, hasArtwork: f[5] == "1"
            )
        }
    }

    // MARK: - Private

    private func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func osascript(_ script: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            let errPipe = Pipe()
            p.standardError = errPipe
            p.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    cont.resume()
                } else {
                    let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "AppleScript error"
                    cont.resume(throwing: AppleMusicError.scriptFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }

    private func osascriptResult(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            let outPipe = Pipe()
            p.standardOutput = outPipe
            p.terminationHandler = { _ in
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                cont.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
            try? p.run()
        }
    }
}

enum AppleMusicError: LocalizedError {
    case scriptFailed(String)
    var errorDescription: String? {
        if case .scriptFailed(let msg) = self { return "Apple Music: \(msg)" }
        return nil
    }
}
