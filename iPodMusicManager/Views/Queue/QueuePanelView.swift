import SwiftUI

struct QueuePanelView: View {
    @EnvironmentObject var queueVM: QueueViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if queueVM.jobs.isEmpty {
                emptyState
            } else {
                jobList
            }

            Divider()
            controls
        }
    }

    private var header: some View {
        HStack {
            Text("Queue")
                .font(.headline)
            Spacer()
            if !queueVM.jobs.isEmpty {
                Button("Clear Done") { queueVM.clearFinished() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Queue is empty")
                .foregroundStyle(.secondary)
            Text("Add tracks from the library or drag FLAC files here.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .dropDestination(for: URL.self) { urls, _ in
            queueVM.enqueueLocalFiles(urls)
            return true
        }
    }

    private var jobList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(queueVM.jobs) { job in
                    JobRow(job: job)
                    Divider().padding(.leading, 14)
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            let total = queueVM.jobs.count
            let done = queueVM.jobs.filter { $0.isFinished }.count
            if total > 0 {
                ProgressView(value: Double(done), total: Double(total))
                    .padding(.horizontal)
                Text("\(done) / \(total) complete")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                if queueVM.isRunning {
                    Button("Pause") { queueVM.pause() }
                        .buttonStyle(.bordered)
                } else {
                    Button("Start") { queueVM.start() }
                        .buttonStyle(.borderedProminent)
                        .disabled(queueVM.jobs.filter { $0.status == .queued }.isEmpty)
                }
                Button("Clear All") { queueVM.clearAll() }
                    .buttonStyle(.bordered)
                    .disabled(queueVM.isRunning)
            }
        }
        .padding()
    }
}

struct JobRow: View {
    @ObservedObject var job: ConversionJob

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(job.track.title).font(.callout).lineLimit(1)
                    Text(job.track.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                statusView
            }

            if job.status == .downloading || job.status == .converting {
                ProgressView(value: job.overallProgress)
                    .progressViewStyle(.linear)
            }

            if let err = job.errorMessage {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusView: some View {
        switch job.status {
        case .queued:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .downloading:
            ProgressView().controlSize(.mini)
        case .converting:
            Image(systemName: "waveform").foregroundStyle(.orange).symbolEffect(.variableColor)
        case .importing:
            Image(systemName: "arrow.down.circle").foregroundStyle(.blue)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .alreadyInLibrary:
            Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        case .skipped:
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }
}
