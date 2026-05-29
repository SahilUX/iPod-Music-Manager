import Foundation

enum JobStatus: String, Equatable {
    case queued, downloading, converting, importing, done, failed, skipped, alreadyInLibrary
}

@MainActor
final class ConversionJob: Identifiable, ObservableObject {
    let id = UUID()
    let track: NavidromeTrack
    let localFlacURL: URL?
    var targetPlaylistName: String?

    @Published var status: JobStatus = .queued
    @Published var downloadProgress: Double = 0
    @Published var convertProgress: Double = 0
    @Published var errorMessage: String?

    init(track: NavidromeTrack, localFlacURL: URL? = nil, targetPlaylistName: String? = nil) {
        self.track = track
        self.localFlacURL = localFlacURL
        self.targetPlaylistName = targetPlaylistName
    }

    var overallProgress: Double {
        switch status {
        case .queued: return 0
        case .downloading: return downloadProgress * 0.4
        case .converting: return 0.4 + convertProgress * 0.45
        case .importing: return 0.9
        case .done, .alreadyInLibrary, .skipped: return 1.0
        case .failed: return 0
        }
    }

    var statusLabel: String {
        switch status {
        case .queued: return "Queued"
        case .downloading: return "Downloading…"
        case .converting: return "Converting…"
        case .importing: return "Importing…"
        case .done: return "Done"
        case .failed: return "Failed"
        case .skipped: return "Skipped"
        case .alreadyInLibrary: return "Already in Library"
        }
    }

    var isFinished: Bool {
        [.done, .failed, .skipped, .alreadyInLibrary].contains(status)
    }
}
