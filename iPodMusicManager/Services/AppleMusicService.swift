import Foundation

final class AppleMusicService {

    func importTrack(m4aURL: URL) async throws {
        try await osascript("""
        tell application "Music"
            activate
            add POSIX file "\(escaped(m4aURL.path))"
        end tell
        """)
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

    func addTrackToPlaylist(title: String, artist: String, playlistName: String) async throws {
        try await osascript("""
        tell application "Music"
            set matches to (tracks of library playlist 1 whose name is "\(escaped(title))" and artist is "\(escaped(artist))")
            if (count of matches) > 0 then
                duplicate item 1 of matches to user playlist "\(escaped(playlistName))"
            end if
        end tell
        """)
    }

    func removeTrackFromPlaylist(title: String, artist: String, playlistName: String) async throws {
        try await osascript("""
        tell application "Music"
            if exists user playlist "\(escaped(playlistName))" then
                set thePlaylist to user playlist "\(escaped(playlistName))"
                set matches to (tracks of thePlaylist whose name is "\(escaped(title))" and artist is "\(escaped(artist))")
                repeat with t in matches
                    delete t
                end repeat
            end if
        end tell
        """)
    }

    func isTrackInLibrary(title: String, artist: String) async -> Bool {
        let result = try? await osascriptResult("""
        tell application "Music"
            return (count of (tracks of library playlist 1 whose name is "\(escaped(title))" and artist is "\(escaped(artist))")) > 0
        end tell
        """)
        return result?.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
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
