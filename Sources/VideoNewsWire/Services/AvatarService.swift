import AppKit
import Foundation

/// Fetches channel avatars from the channel page and caches them locally,
/// so they show offline and without repeated requests.
enum AvatarService {
    static var directory: URL {
        AppPaths.support.appendingPathComponent("avatars", isDirectory: true)
    }

    static func fileURL(for channelID: String) -> URL {
        directory.appendingPathComponent("\(channelID).jpg")
    }

    /// Loads all cached avatars.
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

    /// Downloads a channel's avatar, caches it and returns the image data.
    static func download(channelID: String) async throws -> Data {
        let page = URL(string: "https://www.youtube.com/channel/\(channelID)")!
        let html = try await ChannelResolver.fetchPage(page)

        let patterns: [Regex<(Substring, Substring)>] = [
            #/<meta property="og:image" content="([^"]+)"/#,
            #/"avatar":\{"thumbnails":\[\{"url":"([^"]+)"/#,
        ]
        guard let match = patterns.lazy.compactMap({ html.firstMatch(of: $0) }).first else {
            throw AppError(String(localized: "No channel image found."))
        }
        // Request a small variant (e.g. "=s900-c-k…" → "=s88-c-k…").
        let urlString = String(match.1)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacing(#/=s\d+/#, with: "=s88")
        guard let url = URL(string: urlString.hasPrefix("//") ? "https:" + urlString : urlString) else {
            throw AppError(String(localized: "Invalid image URL."))
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw AppError(String(localized: "Channel image not reachable (HTTP \(http.statusCode))."))
        }
        guard NSImage(data: data) != nil else { throw AppError(String(localized: "The channel image is not an image.")) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(for: channelID), options: .atomic)
        return data
    }

    static func delete(channelID: String) {
        try? FileManager.default.removeItem(at: fileURL(for: channelID))
    }
}
