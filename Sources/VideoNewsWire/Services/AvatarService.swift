import AppKit
import Foundation

/// Lädt die Kanalbilder (Avatare) von der Kanalseite und speichert sie lokal,
/// damit sie offline und ohne erneute Anfragen angezeigt werden.
enum AvatarService {
    static var directory: URL {
        AppPaths.support.appendingPathComponent("avatars", isDirectory: true)
    }

    static func fileURL(for channelID: String) -> URL {
        directory.appendingPathComponent("\(channelID).jpg")
    }

    /// Alle bereits gespeicherten Avatare laden.
    static func loadAll() -> [String: NSImage] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var images: [String: NSImage] = [:]
        for file in files where file.pathExtension == "jpg" {
            if let image = NSImage(contentsOf: file) {
                images[file.deletingPathExtension().lastPathComponent] = image
            }
        }
        return images
    }

    /// Lädt den Avatar eines Kanals, speichert ihn und liefert die Bilddaten.
    static func download(channelID: String) async throws -> Data {
        let page = URL(string: "https://www.youtube.com/channel/\(channelID)")!
        let html = try await ChannelResolver.fetchPage(page)

        let patterns: [Regex<(Substring, Substring)>] = [
            #/<meta property="og:image" content="([^"]+)"/#,
            #/"avatar":\{"thumbnails":\[\{"url":"([^"]+)"/#,
        ]
        guard let match = patterns.lazy.compactMap({ html.firstMatch(of: $0) }).first else {
            throw AppError("Kein Kanalbild gefunden.")
        }
        // Kleine Variante anfordern (z. B. "=s900-c-k…" → "=s88-c-k…").
        let urlString = String(match.1)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacing(#/=s\d+/#, with: "=s88")
        guard let url = URL(string: urlString.hasPrefix("//") ? "https:" + urlString : urlString) else {
            throw AppError("Ungültige Bild-URL.")
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw AppError("Kanalbild nicht erreichbar (HTTP \(http.statusCode)).")
        }
        guard NSImage(data: data) != nil else { throw AppError("Kanalbild ist kein Bild.") }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(for: channelID), options: .atomic)
        return data
    }

    static func delete(channelID: String) {
        try? FileManager.default.removeItem(at: fileURL(for: channelID))
    }
}
