import Foundation

/// Output container/codec the user can target when importing tracks.
enum OutputFormat: String, CaseIterable, Identifiable {
    case aac    // lossy AAC in an .m4a container (Apple's encoder)
    case alac   // Apple Lossless in an .m4a container
    case mp3    // lossy MP3 (libmp3lame)
    case flac   // passthrough — keep the original FLAC

    var id: String { rawValue }

    var label: String {
        switch self {
        case .aac:  return "AAC"
        case .alac: return "Apple Lossless"
        case .mp3:  return "MP3"
        case .flac: return "FLAC (original)"
        }
    }

    var fileExtension: String {
        switch self {
        case .aac, .alac: return "m4a"
        case .mp3:        return "mp3"
        case .flac:       return "flac"
        }
    }

    /// Whether a quality tier applies. Lossless formats ignore it.
    var isLossy: Bool { self == .aac || self == .mp3 }
}

/// User-facing quality presets for the lossy formats. `maximum` is the highest
/// bitrate AAC/MP3 (and the iPod mini) support.
enum QualityTier: String, CaseIterable, Identifiable {
    case maximum, high, medium, low

    var id: String { rawValue }

    var label: String {
        switch self {
        case .maximum: return "Maximum"
        case .high:    return "High"
        case .medium:  return "Medium"
        case .low:     return "Low"
        }
    }

    /// Target bitrate in bits per second.
    var bitrate: Int {
        switch self {
        case .maximum: return 320_000
        case .high:    return 256_000
        case .medium:  return 192_000
        case .low:     return 128_000
        }
    }

    /// "256 kbps", etc. — for display.
    var bitrateLabel: String { "\(bitrate / 1000) kbps" }
}

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

    /// Converts a FLAC file at `flacURL` to the chosen `format`/`quality`. Returns the
    /// output URL (extension matches the format). The caller is responsible for deleting
    /// the returned file when done.
    /// When `embedAlbumArt` is true, the FLAC's embedded cover art (if any) is carried over.
    func convert(flacURL: URL,
                 format: OutputFormat = .aac,
                 quality: QualityTier = .high,
                 embedAlbumArt: Bool = true,
                 progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        switch format {
        case .aac:  return try await convertAAC(flacURL: flacURL, quality: quality, embedAlbumArt: embedAlbumArt, progress: progress)
        case .alac: return try await convertLossless(flacURL: flacURL, embedAlbumArt: embedAlbumArt, progress: progress)
        case .mp3:  return try await convertMP3(flacURL: flacURL, quality: quality, embedAlbumArt: embedAlbumArt, progress: progress)
        case .flac: return try await passthroughFLAC(flacURL: flacURL, embedAlbumArt: embedAlbumArt, progress: progress)
        }
    }

    // MARK: - AAC (.m4a) via Apple's afconvert

    private func convertAAC(flacURL: URL, quality: QualityTier, embedAlbumArt: Bool,
                            progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
        let base = UUID().uuidString
        let wavURL = tmp.appendingPathComponent("\(base).wav")
        let aacTmp = tmp.appendingPathComponent("\(base)_aac.m4a")
        let m4aOut = tmp.appendingPathComponent("\(base).m4a")

        defer {
            try? FileManager.default.removeItem(at: wavURL)
            try? FileManager.default.removeItem(at: aacTmp)
        }

        // 1. FLAC → PCM WAV
        progress(0.05)
        try await run(ffmpegPath, ["-i", flacURL.path, "-ar", "44100", "-y", wavURL.path, "-loglevel", "error"])
        progress(0.40)

        // 2. WAV → AAC/M4A via afconvert (Apple's codec), targeting the chosen bitrate
        try await run("/usr/bin/afconvert",
                      ["-f", "m4af", "-d", "aac", "-b", "\(quality.bitrate)", wavURL.path, aacTmp.path])
        progress(0.75)

        // 3. Inject metadata (and optionally cover art) from the original FLAC
        try await mux(audioFrom: aacTmp, metadataFrom: flacURL, embedAlbumArt: embedAlbumArt, audioCodec: "copy", to: m4aOut)
        progress(1.0)
        return m4aOut
    }

    // MARK: - Apple Lossless (.m4a)

    private func convertLossless(flacURL: URL, embedAlbumArt: Bool,
                                 progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let m4aOut = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        progress(0.10)
        // ffmpeg encodes ALAC directly from FLAC, carrying metadata/art in one pass.
        try await encodeFromFLAC(flacURL: flacURL, audioCodec: ["-c:a", "alac"],
                                 embedAlbumArt: embedAlbumArt, to: m4aOut)
        progress(1.0)
        return m4aOut
    }

    // MARK: - MP3 (.mp3)

    private func convertMP3(flacURL: URL, quality: QualityTier, embedAlbumArt: Bool,
                            progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let mp3Out = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp3")
        progress(0.10)
        try await encodeFromFLAC(flacURL: flacURL,
                                 audioCodec: ["-c:a", "libmp3lame", "-b:a", "\(quality.bitrate / 1000)k", "-id3v2_version", "3"],
                                 embedAlbumArt: embedAlbumArt, to: mp3Out)
        progress(1.0)
        return mp3Out
    }

    // MARK: - FLAC passthrough

    private func passthroughFLAC(flacURL: URL, embedAlbumArt: Bool,
                                 progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let flacOut = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).flac")
        progress(0.10)
        if embedAlbumArt {
            // Keep the original bit-for-bit (caller deletes this copy, not the source).
            try FileManager.default.copyItem(at: flacURL, to: flacOut)
        } else {
            // Re-mux without the attached picture stream.
            try await run(ffmpegPath, ["-i", flacURL.path, "-map", "0:a", "-map_metadata", "0",
                                       "-c:a", "copy", "-y", flacOut.path, "-loglevel", "error"])
        }
        progress(1.0)
        return flacOut
    }

    // MARK: - Shared ffmpeg helpers

    /// Single-pass encode straight from the FLAC (used by ALAC/MP3): maps the audio,
    /// optionally the embedded cover art, copies metadata, and applies `audioCodec`.
    private func encodeFromFLAC(flacURL: URL, audioCodec: [String], embedAlbumArt: Bool, to out: URL) async throws {
        var args = ["-i", flacURL.path, "-map", "0:a"]
        if embedAlbumArt {
            args += ["-map", "0:v?", "-c:v", "copy", "-disposition:v:0", "attached_pic"]
        }
        args += audioCodec
        args += ["-map_metadata", "0", "-y", out.path, "-loglevel", "error"]
        try await run(ffmpegPath, args)
    }

    /// Muxes already-encoded audio with metadata/art from a second file (used by AAC).
    private func mux(audioFrom audio: URL, metadataFrom source: URL, embedAlbumArt: Bool,
                     audioCodec: String, to out: URL) async throws {
        var args = ["-i", audio.path, "-i", source.path, "-map", "0:a"]
        if embedAlbumArt {
            // `?` makes the picture stream optional so sources without art still convert.
            args += ["-map", "1:v?", "-c:v", "copy", "-disposition:v:0", "attached_pic"]
        }
        args += ["-map_metadata", "1", "-c:a", audioCodec, "-y", out.path, "-loglevel", "error"]
        try await run(ffmpegPath, args)
    }

    /// Extracts embedded cover art from a FLAC as JPEG data, or nil if it has none.
    func extractCoverArt(from flacURL: URL) async -> Data? {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: out) }
        do {
            try await run(ffmpegPath, ["-i", flacURL.path, "-an", "-map", "0:v",
                                       "-frames:v", "1", "-y", out.path, "-loglevel", "error"])
            return try? Data(contentsOf: out)
        } catch {
            return nil
        }
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
