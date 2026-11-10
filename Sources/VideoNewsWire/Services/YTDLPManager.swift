import Foundation
import Observation

/// Verwaltet eine eigene yt-dlp-Kopie in ~/Library/Application Support/VideoNewsWire/bin
/// und hält sie automatisch aktuell (YouTube ändert sich häufig, yt-dlp zieht nach).
@MainActor @Observable
final class YTDLPManager {
    static let shared = YTDLPManager()

    private(set) var version: String?
    private(set) var isBusy = false
    var statusMessage: String?
    /// Fortschritt laufender Downloads (Video-ID → 0…1).
    private(set) var downloadProgress: [String: Double] = [:]

    let binaryURL = AppPaths.support.appendingPathComponent("bin/yt-dlp")
    static let releaseURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!

    var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: binaryURL.path) }

    // MARK: Installation & Updates

    func refreshVersion() async {
        guard isInstalled else { version = nil; return }
        if let result = try? await ProcessRunner.run(binaryURL, arguments: ["--version"]), result.succeeded {
            version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func install() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        statusMessage = "Lade yt-dlp herunter…"
        do {
            let (tempURL, response) = try await URLSession.shared.download(from: Self.releaseURL)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw AppError("Download fehlgeschlagen (HTTP \(http.statusCode)).")
            }
            let fm = FileManager.default
            try fm.createDirectory(at: binaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: binaryURL.path) { try fm.removeItem(at: binaryURL) }
            try fm.moveItem(at: tempURL, to: binaryURL)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)
            UserDefaults.standard.set(Date(), forKey: Prefs.ytdlpLastUpdate)
            await refreshVersion()
            statusMessage = "yt-dlp \(version ?? "") installiert."
        } catch {
            statusMessage = "Installation fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func update() async {
        guard isInstalled else { await install(); return }
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        statusMessage = "Suche nach Updates…"
        do {
            let result = try await ProcessRunner.run(binaryURL, arguments: ["-U"])
            UserDefaults.standard.set(Date(), forKey: Prefs.ytdlpLastUpdate)
            await refreshVersion()
            if result.succeeded {
                let last = result.stdout.split(separator: "\n").last.map(String.init) ?? ""
                statusMessage = last.isEmpty ? "yt-dlp \(version ?? "") ist aktuell." : last
            } else {
                statusMessage = "Update fehlgeschlagen: \(result.errorSummary)"
            }
        } catch {
            statusMessage = "Update fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    /// Prüft beim Start höchstens alle drei Tage auf ein yt-dlp-Update.
    func updateIfNeeded() async {
        await refreshVersion()
        guard isInstalled, UserDefaults.standard.bool(forKey: Prefs.autoUpdateYTDLP) else { return }
        let last = UserDefaults.standard.object(forKey: Prefs.ytdlpLastUpdate) as? Date ?? .distantPast
        if Date().timeIntervalSince(last) > 3 * 24 * 3600 {
            await update()
        }
    }

    // MARK: Download

    func download(_ video: Video, to folder: URL, maxHeight: Int) async throws -> URL {
        guard isInstalled else {
            throw AppError("yt-dlp ist nicht installiert (Einstellungen → Downloads).")
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let id = video.id
        downloadProgress[id] = 0
        defer { downloadProgress[id] = nil }

        var args = [
            "--no-playlist", "--newline", "--progress", "--color", "never",
            "--progress-template", "download:VNWPROGRESS %(progress._percent_str)s",
            "--print", "after_move:filepath",
            "-o", folder.path + "/%(channel)s - %(title)s [%(id)s].%(ext)s",
        ]
        if let ffmpeg = ProcessRunner.findTool("ffmpeg") {
            // Mit ffmpeg: getrennte Video-/Audiospuren in guter Qualität zusammenführen.
            args += [
                "--ffmpeg-location", ffmpeg.path,
                "-f", "bv*[height<=\(maxHeight)][ext=mp4]+ba[ext=m4a]/b[height<=\(maxHeight)][ext=mp4]/b[ext=mp4]/b",
                "--merge-output-format", "mp4",
            ]
        } else {
            // Ohne ffmpeg nur kombinierte Formate (meist max. 720p).
            args += ["-f", "b[ext=mp4]/b"]
        }
        args.append(video.watchURL.absoluteString)

        let result = try await ProcessRunner.run(binaryURL, arguments: args) { line in
            guard let range = line.range(of: "VNWPROGRESS ") else { return }
            let number = line[range.upperBound...]
                .replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let value = Double(number) {
                Task { @MainActor in self.downloadProgress[id] = value / 100 }
            }
        }
        guard result.succeeded else { throw AppError(result.errorSummary) }

        let path = result.stdout
            .split(separator: "\n").map(String.init)
            .last(where: { FileManager.default.fileExists(atPath: $0) })
        guard let path else { throw AppError("Download beendet, aber Datei nicht gefunden.") }
        return URL(fileURLWithPath: path)
    }

    // MARK: Transkript (für die KI-Zusammenfassung)

    /// Lädt Untertitel (bevorzugt die automatischen Original-Untertitel) und liefert reinen Text.
    func transcript(for videoID: String) async throws -> String? {
        guard isInstalled else { return nil }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("vnw-subs-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        _ = try await ProcessRunner.run(binaryURL, arguments: [
            "--skip-download", "--write-subs", "--write-auto-subs",
            "--sub-langs", "de-orig,en-orig,.*-orig,de,en",
            "--sub-format", "vtt", "--no-playlist",
            "-o", dir.path + "/sub.%(ext)s",
            "https://www.youtube.com/watch?v=\(videoID)",
        ])

        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let preferred = ["de-orig", "en-orig", "de", "en"]
        func rank(_ url: URL) -> Int {
            // Dateiname: sub.<sprache>.vtt
            let lang = url.deletingPathExtension().pathExtension
            if let index = preferred.firstIndex(of: lang) { return index }
            return lang.hasSuffix("-orig") ? 2 : 10
        }
        guard let chosen = files.filter({ $0.pathExtension == "vtt" }).min(by: { rank($0) < rank($1) }),
              let raw = try? String(contentsOf: chosen, encoding: .utf8) else { return nil }
        let text = VTT.plainText(raw)
        return text.isEmpty ? nil : text
    }

    // MARK: Kanäle

    /// Liest die Abos des im Browser angemeldeten YouTube-Kontos über dessen Cookies aus.
    func subscribedChannels(browser: String) async throws -> [(id: String, title: String)] {
        guard isInstalled else { throw AppError("yt-dlp ist nicht installiert.") }
        let result = try await ProcessRunner.run(binaryURL, arguments: [
            "--cookies-from-browser", browser, "--flat-playlist",
            "--print", "%(id)s\t%(channel_id)s\t%(title)s\t%(channel)s",
            "https://www.youtube.com/feed/channels",
        ])
        guard result.succeeded else { throw AppError(result.errorSummary) }
        return result.stdout.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let id = fields.first(where: ChannelResolver.isChannelID) else { return nil }
            let title = fields.dropFirst(2).first(where: { !$0.isEmpty && $0 != "NA" }) ?? id
            return (id, title)
        }
    }

    /// Fallback zur Kanal-Erkennung, falls das Auslesen der Kanalseite scheitert.
    func channelID(for url: String) async throws -> String? {
        guard isInstalled else { return nil }
        let result = try await ProcessRunner.run(binaryURL, arguments: [
            "--flat-playlist", "-I", "1",
            "--print", "%(channel_id)s\t%(playlist_channel_id)s", url,
        ])
        return result.stdout
            .split(whereSeparator: { $0 == "\n" || $0 == "\t" })
            .map(String.init)
            .first(where: ChannelResolver.isChannelID)
    }
}

/// Wandelt WebVTT-Untertitel in Fließtext um (inkl. Entfernen der rollenden Duplikate
/// bei automatischen YouTube-Untertiteln).
enum VTT {
    static func plainText(_ raw: String) -> String {
        var output: [String] = []
        for rawLine in raw.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line == "WEBVTT" || line.contains("-->") || Int(line) != nil
                || line.hasPrefix("Kind:") || line.hasPrefix("Language:")
                || line.hasPrefix("NOTE") || line.hasPrefix("STYLE") {
                continue
            }
            var text = line.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            for (entity, char) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " "] {
                text = text.replacingOccurrences(of: entity, with: char)
            }
            text = text.trimmingCharacters(in: .whitespaces)
            if text.isEmpty || output.suffix(2).contains(text) { continue }
            output.append(text)
        }
        return output.joined(separator: " ")
    }
}
