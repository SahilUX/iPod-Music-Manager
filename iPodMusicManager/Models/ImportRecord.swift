import Foundation

/// A track this app converted and imported into Apple Music, plus enough provenance
/// to re-source and re-convert it later when the user changes format/quality/art.
struct ImportRecord: Codable, Identifiable, Hashable {
    enum Source: Codable, Hashable {
        case navidrome(id: String)
        case local(path: String)
    }

    let title: String
    let artist: String
    var source: Source

    // Settings the file was produced with — compared against current settings to
    // decide whether a track is out of date.
    var format: String          // OutputFormat.rawValue
    var quality: String         // QualityTier.rawValue
    var embedAlbumArt: Bool

    var importedAt: Date

    /// Stable identity: a track is one logical (title, artist) pair in the library.
    var id: String { ImportRecord.key(title: title, artist: artist) }

    /// Uses the shared tolerant matcher so records, scanning, and self-heal all identify
    /// a track the same way Navidrome and the file's embedded tags can be reconciled.
    static func key(title: String, artist: String) -> String {
        TrackMatch.key(title: title, artist: artist)
    }
}

/// Tolerant matching across data sources whose metadata often disagrees — Navidrome's
/// reported tags vs. the file's embedded tags. The two clash most on multi-artist tracks
/// ("Rex Vijayan, Pradeep Kumar, Sithara" vs. just "Rex Vijayan") and "feat." titles.
/// Reducing each track to (normalized title | primary artist) makes logically-identical
/// tracks produce the same key from either source, so duplicates are detected reliably.
enum TrackMatch {
    static func key(title: String, artist: String) -> String {
        "\(normalizedTitle(title))\u{1}\(primaryArtist(artist))"
    }

    /// Lowercased, accent/quote-folded title with "(feat. …)" / "feat. …" stripped and
    /// punctuation removed, so title variants between sources collapse together.
    static func normalizedTitle(_ s: String) -> String {
        var t = fold(s)
        for p in ["\\((feat|ft)\\.?[^)]*\\)", "\\b(feat|ft)\\.?.*$"] {
            t = t.replacingOccurrences(of: p, with: " ", options: [.regularExpression])
        }
        return collapse(t)
    }

    /// The first credited artist, used as a representation-stable anchor: both
    /// "A, B, C" and "A feat. B" reduce to "a" from either source.
    static func primaryArtist(_ s: String) -> String {
        var primary = fold(s)
        for sep in [",", "&", ";", "/", " feat", " ft"] {
            if let r = primary.range(of: sep) { primary = String(primary[..<r.lowerBound]) }
        }
        return collapse(primary)
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
    }

    /// Keeps alphanumerics + spaces, collapses runs of whitespace, trims.
    private static func collapse(_ s: String) -> String {
        s.replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: [.regularExpression])
            .replacingOccurrences(of: "\\s+", with: " ", options: [.regularExpression])
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Persistent store of imported-track provenance, shared between the import queue
/// (which writes records) and the re-processor (which reads/updates them).
@MainActor
final class ImportRecordStore: ObservableObject {
    @Published private(set) var records: [ImportRecord] = []

    private let storageKey = "com.sahil.ipm.importRecords"

    init() { load() }

    /// Insert or replace the record for a (title, artist) pair.
    func upsert(_ record: ImportRecord) {
        if let idx = records.firstIndex(where: { $0.id == record.id }) {
            records[idx] = record
        } else {
            records.append(record)
        }
        save()
    }

    func remove(title: String, artist: String) {
        let key = ImportRecord.key(title: title, artist: artist)
        records.removeAll { $0.id == key }
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([ImportRecord].self, from: data) else { return }
        records = saved
    }
}
