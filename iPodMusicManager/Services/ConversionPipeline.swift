import Foundation

final class ConversionPipeline {
    let ffmpegPath: String

    init() {
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ffmpeg") {
            ffmpegPath = "/opt/homebrew/bin/ffmpeg"
        } else if FileManager.default.fileExists(atPath: "/usr/local/bin/ffmpeg") {
            ffmpegPath = "/usr/local/bin/ffmpeg"
        } else {
            ffmpegPath = "/opt/homebrew/bin/ffmpeg"
        }
    }

    var isAvailable: Bool { FileManager.default.fileExists(atPath: ffmpegPath) }

    /// Converts a FLAC file at `flacURL` to a tagged M4A. Returns the M4A URL.
    /// The caller is responsible for deleting the returned file when done.
    func convert(flacURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
        let base = UUID().uuidString
        let wavURL  = tmp.appendingPathComponent("\(base).wav")
        let aacTmp  = tmp.appendingPathComponent("\(base)_aac.m4a")
        let m4aOut  = tmp.appendingPathComponent("\(base).m4a")

        defer {
            try? FileManager.default.removeItem(at: wavURL)
            try? FileManager.default.removeItem(at: aacTmp)
        }

        // 1. FLAC → PCM WAV
        progress(0.05)
        try await run(ffmpegPath, ["-i", flacURL.path, "-ar", "44100", "-y", wavURL.path, "-loglevel", "error"])
        progress(0.40)

        // 2. WAV → AAC/M4A via afconvert (Apple's codec)
        try await run("/usr/bin/afconvert", ["-f", "m4af", "-d", "aac", "-s", "3", "-u", "pgcm", "2", wavURL.path, aacTmp.path])
        progress(0.75)

        // 3. Inject full metadata from original FLAC into the M4A (no re-encode)
        try await run(ffmpegPath, [
            "-i", aacTmp.path, "-i", flacURL.path,
            "-map", "0:a", "-map_metadata", "1",
            "-c", "copy", "-y", m4aOut.path, "-loglevel", "error"
        ])
        progress(1.0)

        return m4aOut
    }

    private func run(_ executable: String, _ args: [String]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: executable)
            proc.arguments = args
            let errPipe = Pipe()
            proc.standardError = errPipe
            proc.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    cont.resume()
                } else {
                    let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    cont.resume(throwing: ConversionError.processFailed(executable, p.terminationStatus, msg))
                }
            }
            do { try proc.run() } catch { cont.resume(throwing: error) }
        }
    }
}

enum ConversionError: LocalizedError {
    case processFailed(String, Int32, String)

    var errorDescription: String? {
        if case .processFailed(let name, let code, let msg) = self {
            let short = URL(fileURLWithPath: name).lastPathComponent
            return "\(short) exited \(code)\(msg.isEmpty ? "" : ": \(msg.prefix(200))")"
        }
        return nil
    }
}
