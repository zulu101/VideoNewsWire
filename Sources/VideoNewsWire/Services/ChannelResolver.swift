import Foundation

/// Ermittelt aus einer Eingabe (URL, @Handle, Kanal-ID, Video-URL) die Kanal-ID (UC…).
@MainActor
enum ChannelResolver {
    nonisolated static func isChannelID(_ string: String) -> Bool {
        string.wholeMatch(of: #/UC[A-Za-z0-9_-]{22}/#) != nil
    }

    static func resolve(_ input: String) async throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppError("Bitte eine Kanal-URL, ein @Handle oder eine Kanal-ID eingeben.") }

        if isChannelID(trimmed) { return trimmed }
        if let match = trimmed.firstMatch(of: #/\/channel\/(UC[A-Za-z0-9_-]{22})/#) {
            return String(match.1)
        }

        let url = try pageURL(for: trimmed)
        if let id = try? await scrape(url) { return id }
        if let id = try? await YTDLPManager.shared.channelID(for: url.absoluteString) { return id }
        throw AppError("Kanal nicht gefunden. Tipp: Kanal-URL aus dem Browser kopieren.")
    }

    private static func pageURL(for input: String) throws -> URL {
        var string = input
        if string.hasPrefix("@") {
            string = "https://www.youtube.com/" + string
        } else if !string.contains("/") && !string.contains(".") {
            string = "https://www.youtube.com/@" + string
        } else if !string.lowercased().hasPrefix("http") {
            string = "https://" + string
        }
        guard let url = URL(string: string), let host = url.host?.lowercased(),
              host.hasSuffix("youtube.com") || host == "youtu.be" else {
            throw AppError("Das sieht nicht nach einer YouTube-Adresse aus.")
        }
        return url
    }

    private static func scrape(_ url: URL) async throws -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.httpShouldHandleCookies = false
        // Umgeht die EU-Cookie-Einwilligungsseite.
        request.setValue("SOCS=CAI; CONSENT=YES+cb", forHTTPHeaderField: "Cookie")
        request.setValue("de-DE,de;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else { return nil }

        let patterns: [Regex<(Substring, Substring)>] = [
            #/<link rel="canonical" href="https:\/\/www\.youtube\.com\/channel\/(UC[A-Za-z0-9_-]{22})"/#,
            #/"externalId":"(UC[A-Za-z0-9_-]{22})"/#,
            #/itemprop="identifier" content="(UC[A-Za-z0-9_-]{22})"/#,
            #/"channelId":"(UC[A-Za-z0-9_-]{22})"/#,
        ]
        for pattern in patterns {
            if let match = html.firstMatch(of: pattern) { return String(match.1) }
        }
        return nil
    }
}
