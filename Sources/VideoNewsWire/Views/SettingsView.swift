import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Allgemein", systemImage: "gearshape") { GeneralSettingsView() }
            Tab("Downloads", systemImage: "arrow.down.circle") { DownloadSettingsView() }
            Tab("KI", systemImage: "sparkles") { AISettingsView() }
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
            Section("Weniger Ablenkung") {
                Toggle("Shorts ausblenden", isOn: $hideShorts)
                Toggle("Vorschaubilder anzeigen", isOn: $showThumbnails)
                Text("Thumbnails sind auf Klicks optimiert. Ohne sie entscheidest du anhand des Titels.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Zähler für ungesehene Videos anzeigen", isOn: $showUnreadCounts)
            }
            Section("Verhalten") {
                Toggle("Video beim Öffnen als gesehen markieren", isOn: $markWatchedOnOpen)
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
            Section("Speicherort") {
                LabeledContent("Ordner") {
                    HStack {
                        Text(Prefs.downloadFolderURL.path(percentEncoded: false))
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Ändern…", action: chooseFolder)
                    }
                }
                Picker("Maximale Auflösung", selection: $maxHeight) {
                    Text("720p").tag(720)
                    Text("1080p").tag(1080)
                    Text("1440p").tag(1440)
                    Text("2160p (4K)").tag(2160)
                }
            }

            Section("yt-dlp") {
                LabeledContent("Status") {
                    if ytdlp.isInstalled {
                        Text("Installiert – Version \(ytdlp.version ?? "?")")
                    } else {
                        Text("Nicht installiert").foregroundStyle(.orange)
                    }
                }
                HStack {
                    if ytdlp.isInstalled {
                        Button("Jetzt aktualisieren") { Task { await ytdlp.update() } }
                    } else {
                        Button("yt-dlp installieren") { Task { await ytdlp.install() } }
                    }
                    if ytdlp.isBusy { ProgressView().controlSize(.small) }
                }
                .disabled(ytdlp.isBusy)
                if let status = ytdlp.statusMessage {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Automatisch aktualisieren (alle 3 Tage beim Start)", isOn: $autoUpdate)
                Text("yt-dlp wird von github.com/yt-dlp/yt-dlp geladen und in „~/Library/Application Support/VideoNewsWire“ abgelegt.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Optionale Helfer (Homebrew)") {
                toolRow("ffmpeg", purpose: "für Auflösungen über 720p (Video und Ton zusammenführen)")
                toolRow("deno", purpose: "von yt-dlp empfohlen, damit alle YouTube-Formate verfügbar sind")
                Text("Installation: `brew install ffmpeg deno`")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await ytdlp.refreshVersion() }
    }

    private func toolRow(_ name: String, purpose: String) -> some View {
        let found = ProcessRunner.findTool(name) != nil
        return LabeledContent {
            Label(found ? "Gefunden" : "Nicht gefunden",
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
                    Label("Verfügbar", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Text("Zusammenfassungen werden vollständig auf diesem Mac mit Apples Foundation Models erstellt. "
                     + "Es werden keine Daten an einen KI-Dienst gesendet. Grundlage ist das Transkript "
                     + "(Untertitel via yt-dlp), ersatzweise die Videobeschreibung.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
