import SwiftUI

enum AppIconChoice: String, CaseIterable {
    case waveform   = "AppIcon"
    case clickWheel = "AppIcon-ClickWheel"

    var label: String {
        switch self {
        case .waveform:   return "Waveform"
        case .clickWheel: return "ClickWheel"
        }
    }

    var nsImage: NSImage? {
        // Asset catalog appiconsets are accessible via NSImage(named:) on macOS
        if let img = NSImage(named: rawValue) { return img }
        // Fallback: load compiled .icns from bundle
        if let url = Bundle.main.url(forResource: rawValue, withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        return nil
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var navidrome: NavidromeClient
    @EnvironmentObject var reprocessor: LibraryReprocessor

    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var connectionStatus = ""
    @State private var isTesting = false
    @State private var ffmpegStatus = ""
    @State private var activeTab: SettingsTab = .navidrome
    @AppStorage("preferredAppIcon") private var preferredIconRaw: String = AppIconChoice.waveform.rawValue
    @AppStorage("embedAlbumArt") private var embedAlbumArt: Bool = true
    @AppStorage("outputFormat") private var outputFormatRaw: String = OutputFormat.aac.rawValue
    @AppStorage("outputQuality") private var outputQualityRaw: String = QualityTier.high.rawValue

    private var outputFormat: OutputFormat { OutputFormat(rawValue: outputFormatRaw) ?? .aac }
    private var outputQuality: QualityTier { QualityTier(rawValue: outputQualityRaw) ?? .high }

    enum SettingsTab { case navidrome, general }

    private var preferredIcon: AppIconChoice {
        AppIconChoice(rawValue: preferredIconRaw) ?? .waveform
    }

    var body: some View {
        VStack(spacing: 0) {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // App Icon picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("App Icon")
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        ForEach(AppIconChoice.allCases, id: \.self) { choice in
                            iconOption(choice)
                        }
                        Spacer()
                    }
                }

                // ffmpeg
                VStack(alignment: .leading, spacing: 4) {
                    Text("Conversion")
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(.secondary)
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

                        Divider().padding(.leading, 12)
                        HStack {
                            Text("Format")
                            Spacer()
                            Picker("", selection: $outputFormatRaw) {
                                ForEach(OutputFormat.allCases) { fmt in
                                    Text(fmt.label).tag(fmt.rawValue)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        .padding(12)

                        if outputFormat == .flac {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Apple Music can't import FLAC, so these tracks won't appear in your library or on iPod. For lossless playback on Apple Music and iPod, choose Apple Lossless.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                        }

                        Divider().padding(.leading, 12)
                        HStack {
                            Text("Quality")
                            Spacer()
                            if outputFormat.isLossy {
                                Picker("", selection: $outputQualityRaw) {
                                    ForEach(QualityTier.allCases) { tier in
                                        Text("\(tier.label) · \(tier.bitrateLabel)").tag(tier.rawValue)
                                    }
                                }
                                .labelsHidden()
                                .fixedSize()
                            } else {
                                Text("Lossless")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)

                        Divider().padding(.leading, 12)
                        Toggle(isOn: $embedAlbumArt) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Embed album art")
                                Text("Copy cover art from the source file into converted tracks.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Re-process existing library
                reprocessSection

                // Notifications
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notifications")
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(.secondary)
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
            }
            .padding(16)
        }
    }

    // MARK: - Re-process library

    private var reprocessSection: some View {
        let outdated = reprocessor.outdatedCount(
            format: outputFormat, quality: outputQuality, embedArt: embedAlbumArt
        )
        return VStack(alignment: .leading, spacing: 4) {
            Text("Existing Library")
                .font(.subheadline).fontWeight(.semibold).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("Scan your Apple Music library to find tracks that can be re-processed, then re-apply the settings above. Format or quality changes re-download and replace from the source; album-art changes update in place. Tracks with no recoverable source are skipped.")
                    .font(.caption).foregroundStyle(.secondary)

                if reprocessor.isScanning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(reprocessor.statusText.isEmpty ? "Scanning…" : reprocessor.statusText)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else if reprocessor.isRunning {
                    ProgressView(value: reprocessor.progress)
                    Text(reprocessor.statusText)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    HStack(spacing: 12) {
                        Button("Scan Library") {
                            Task { await reprocessor.scanLibrary() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(outdated > 0 ? "Re-process \(outdated) Track\(outdated == 1 ? "" : "s")" : "Re-process Library") {
                            Task {
                                await reprocessor.reprocessAll(
                                    format: outputFormat, quality: outputQuality, embedArt: embedAlbumArt
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(outdated == 0)
                    }

                    if let summary = reprocessor.lastSummary {
                        Text(summary)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    } else if let scan = reprocessor.scanSummary {
                        Text(outdated > 0 ? "\(scan) — \(outdated) differ from current settings."
                                          : "\(scan) All match the current settings.")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    } else {
                        Text("Scan your library to get started.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func iconOption(_ choice: AppIconChoice) -> some View {
        let selected = preferredIcon == choice
        Button {
            preferredIconRaw = choice.rawValue
            if let img = choice.nsImage {
                NSApp.applicationIconImage = img
            }
        } label: {
            VStack(spacing: 6) {
                Group {
                    if let img = choice.nsImage {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.secondary.opacity(0.2))
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2.5)
                )
                .shadow(color: selected ? .accentColor.opacity(0.4) : .clear, radius: 4)

                Text(choice.label)
                    .font(.caption)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
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
