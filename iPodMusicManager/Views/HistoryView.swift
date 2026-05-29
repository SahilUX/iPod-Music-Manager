import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var queueVM: QueueViewModel

    private var finished: [ConversionJob] {
        queueVM.jobs.filter(\.isFinished).reversed()
    }

    var body: some View {
        Group {
            if finished.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Completed conversions will appear here.")
                )
            } else {
                List(finished) { job in
                    HStack(spacing: 12) {
                        Image(systemName: statusIcon(job.status))
                            .foregroundStyle(statusColor(job.status))
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.track.title).lineLimit(1)
                            Text(job.track.artist ?? "").font(.caption).foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(job.statusLabel)
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(statusColor(job.status).opacity(0.12))
                            .foregroundStyle(statusColor(job.status))
                            .clipShape(Capsule())
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("History")
    }

    private func statusIcon(_ s: JobStatus) -> String {
        switch s {
        case .done: return "checkmark.circle.fill"
        case .alreadyInLibrary: return "checkmark.circle"
        case .failed: return "exclamationmark.circle.fill"
        case .skipped: return "minus.circle"
        default: return "circle"
        }
    }

    private func statusColor(_ s: JobStatus) -> Color {
        switch s {
        case .done: return .green
        case .alreadyInLibrary: return .secondary
        case .failed: return .red
        case .skipped: return .secondary
        default: return .secondary
        }
    }
}
