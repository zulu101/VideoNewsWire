import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettingsView() }
            Tab("Downloads", systemImage: "arrow.down.circle") { DownloadSettingsView() }
            Tab("AI", systemImage: "sparkles") { AISettingsView() }
        }
        .frame(width: 560)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage(Prefs.hideShorts) private var hideShorts = true
    @AppStorage(Prefs.showThumbnails) private var showThumbnails = false
    @AppStorage(Prefs.showUnreadCounts) private var showUnreadCounts = false
    @AppStorage(Prefs.markWatchedOnOpen) private var markWatchedOnOpen = true

    var body: some View {
        Form {
            Section("Fewer Distractions") {
                Toggle("Hide Shorts", isOn: $hideShorts)
                Toggle("Show thumbnails", isOn: $showThumbnails)
                Text("Thumbnails are optimized for clicks. Without them, you decide by the title.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show counts of unwatched videos", isOn: $showUnreadCounts)
            }
            Section("Behavior") {
                Toggle("Mark videos as watched when opened", isOn: $markWatchedOnOpen)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DownloadSettingsView: View {
    @Environment(YTDLPManager.self) private var ytdlp
    @AppStorage(Prefs.downloadFolder) private var downloadFolder = ""
    @AppStorage(Prefs.maxDownloadHeight) private var maxHeight = 1080
    @AppStorage(Prefs.autoUpdateYTDLP) private var autoUpdate = true

    var body: some View {
        Form {
            Section("Location") {
                LabeledContent("Folder") {
                    HStack {
                        Text(Prefs.downloadFolderURL.path(percentEncoded: false))
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Change…", action: chooseFolder)
                    }
                }
                Picker("Maximum resolution", selection: $maxHeight) {
                    Text("720p").tag(720)
                    Text("1080p").tag(1080)
                    Text("1440p").tag(1440)
                    Text("2160p (4K)").tag(2160)
                }
            }

            Section("yt-dlp") {
                LabeledContent("Status") {
                    if ytdlp.isInstalled {
                        Text("Installed – version \(ytdlp.version ?? "?")")
                    } else {
                        Text("Not installed").foregroundStyle(.orange)
                    }
                }
                HStack {
                    if ytdlp.isInstalled {
                        Button("Update Now") { Task { await ytdlp.update() } }
                    } else {
                        Button("Install yt-dlp") { Task { await ytdlp.install() } }
                    }
                    if ytdlp.isBusy { ProgressView().controlSize(.small) }
                }
                .disabled(ytdlp.isBusy)
                if let status = ytdlp.statusMessage {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Update automatically (every 3 days at launch)", isOn: $autoUpdate)
                Text("yt-dlp is downloaded from github.com/yt-dlp/yt-dlp and stored in “~/Library/Application Support/VideoNewsWire”.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Optional Helpers (Homebrew)") {
                toolRow("ffmpeg", purpose: "for resolutions above 720p (merges video and audio)")
                toolRow("deno", purpose: "recommended by yt-dlp so all YouTube formats are available")
                Text("Installation: `brew install ffmpeg deno`")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await ytdlp.refreshVersion() }
    }

    private func toolRow(_ name: String, purpose: LocalizedStringKey) -> some View {
        let found = ProcessRunner.findTool(name) != nil
        return LabeledContent {
            Label(found ? String(localized: "Found") : String(localized: "Not found"),
                  systemImage: found ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(found ? .green : .secondary)
        } label: {
            VStack(alignment: .leading) {
                Text(name)
                Text(purpose).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = Prefs.downloadFolderURL
        if panel.runModal() == .OK, let url = panel.url {
            downloadFolder = url.path
        }
    }
}

private struct AISettingsView: View {
    var body: some View {
        Form {
            Section("Apple Intelligence") {
                if let reason = Summarizer.unavailableReason {
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else {
                    Label("Available", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Text("Summaries are created entirely on this Mac with Apple’s Foundation Models. No data is sent to an AI service. They are based on the transcript (subtitles via yt-dlp), or the video description as a fallback.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
