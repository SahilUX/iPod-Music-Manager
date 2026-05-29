import SwiftUI

struct LocalDropView: View {
    @EnvironmentObject var queueVM: QueueViewModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)

            Text("Drop FLAC Files Here")
                .font(.title3).fontWeight(.semibold)

            Text("Drag any .flac files or folders from Finder to convert them and add to Apple Music.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)

            Button("Choose Files…") { openPanel() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .padding(24)
        )
        .dropDestination(for: URL.self) { urls, _ in
            queueVM.enqueueLocalFiles(urls)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "flac")!]
        if panel.runModal() == .OK {
            queueVM.enqueueLocalFiles(panel.urls)
        }
    }
}
