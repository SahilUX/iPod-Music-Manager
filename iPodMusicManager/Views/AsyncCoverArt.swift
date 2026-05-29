import SwiftUI

struct AsyncCoverArt: View {
    let url: URL?

    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    Color.secondary.opacity(0.15)
                        .overlay(ProgressView().controlSize(.mini))
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Color.secondary.opacity(0.15)
            .overlay(
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            )
    }
}
