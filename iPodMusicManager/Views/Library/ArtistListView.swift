import SwiftUI

struct ArtistListView: View {
    @EnvironmentObject var libraryVM: LibraryViewModel
    @EnvironmentObject var navidrome: NavidromeClient

    var body: some View {
        Group {
            if !navidrome.isConnected && libraryVM.artists.isEmpty {
                notConnectedView
            } else if libraryVM.isLoading && libraryVM.artists.isEmpty {
                ProgressView("Loading artists…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if libraryVM.artists.isEmpty {
                ContentUnavailableView("No Artists", systemImage: "music.mic", description: Text("Your Navidrome library is empty."))
            } else {
                List(libraryVM.artists, selection: Binding<NavidromeArtist?>(
                    get: { nil },
                    set: { artist in
                        if let a = artist { Task { await libraryVM.selectArtist(a) } }
                    }
                )) { artist in
                    HStack {
                        AsyncCoverArt(url: libraryVM.coverArtURL(id: artist.coverArt, size: 48))
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(artist.name)
                            if let count = artist.albumCount {
                                Text("\(count) album\(count == 1 ? "" : "s")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { Task { await libraryVM.selectArtist(artist) } }
                }
                .listStyle(.inset)
            }
        }
        .task {
            if navidrome.isConnected && libraryVM.artists.isEmpty {
                await libraryVM.loadArtists()
            }
        }
    }

    private var notConnectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Navidrome Server Connected")
                .font(.title3).fontWeight(.semibold)
            Text("Add your server in Settings to browse your library.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
