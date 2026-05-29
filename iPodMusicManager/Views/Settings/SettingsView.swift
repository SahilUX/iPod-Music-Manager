import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var navidrome: NavidromeClient

    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var connectionStatus = ""
    @State private var isTesting = false
    @State private var ffmpegStatus = ""
    @State private var activeTab: SettingsTab = .navidrome

    enum SettingsTab { case navidrome, general }

    var body: some View {
        VStack(spacing: 0) {
            // Custom tab bar — avoids NSTabViewController/ViewBridge noise
            Picker("", selection: $activeTab) {
                Text("Navidrome").tag(SettingsTab.navidrome)
                Text("General").tag(SettingsTab.general)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 120)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            Group {
                if activeTab == .navidrome {
                    navidromeTab
                } else {
                    generalTab
                }
            }
            .frame(width: 460, height: 300)

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            serverURL = navidrome.baseURL
            username = navidrome.username
            password = navidrome.password
            checkFFmpeg()
        }
    }

    // MARK: - Navidrome tab

    private var navidromeTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Grouped fields
            VStack(spacing: 0) {
                fieldRow(label: "URL") {
                    TextField("https://music.example.com", text: $serverURL)
                        .textFieldStyle(.plain)
                }
                Divider().padding(.leading, 12)
                fieldRow(label: "Username") {
                    TextField("", text: $username)
                        .textFieldStyle(.plain)
                }
                Divider().padding(.leading, 12)
                fieldRow(label: "Password") {
                    SecureField("", text: $password)
                        .textFieldStyle(.plain)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Save & Test row
            HStack(spacing: 12) {
                Button("Save & Test") {
                    navidrome.configure(url: serverURL, username: username, password: password)
                    isTesting = true
                    connectionStatus = "Testing…"
                    Task {
                        do {
                            try await navidrome.ping()
                            connectionStatus = "● Connected — Navidrome \(navidrome.serverVersion ?? "")"
                        } catch {
                            connectionStatus = "✗ \(error.localizedDescription)"
                        }
                        isTesting = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTesting)

                if isTesting {
                    ProgressView().controlSize(.small)
                } else if !connectionStatus.isEmpty {
                    Text(connectionStatus)
                        .font(.caption)
                        .foregroundStyle(connectionStatus.hasPrefix("●") ? .green : .red)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(16)
    }

    // MARK: - General tab

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Conversion").font(.subheadline).fontWeight(.semibold).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    HStack {
                        Text("ffmpeg")
                        Spacer()
                        Text(ffmpegStatus)
                            .font(.caption)
                            .foregroundStyle(ffmpegStatus.hasPrefix("✓") ? .green : .red)
                            .lineLimit(1)
                    }
                    .padding(12)
                    Divider().padding(.leading, 12)
                    Text("Install via: brew install ffmpeg")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(12)
                }
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Notifications").font(.subheadline).fontWeight(.semibold).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sent when batch jobs complete and when linked playlists sync.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Notification Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Spacer()
        }
        .padding(16)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func fieldRow(label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func checkFFmpeg() {
        let pipeline = ConversionPipeline()
        ffmpegStatus = pipeline.isAvailable
            ? "✓ Found at \(pipeline.ffmpegPath)"
            : "✗ Not found — install via Homebrew"
    }
}
