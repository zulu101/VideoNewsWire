import Foundation

/// Resolves an input (URL, @handle, channel ID, video URL) to a channel ID (UC…).
@MainActor
enum ChannelResolver {
    nonisolated static func isChannelID(_ string: String) -> Bool {
        string.wholeMatch(of: #/UC[A-Za-z0-9_-]{22}/#) != nil
    }

    static func resolve(_ input: String) async throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppError(String(localized: "Please enter a channel URL, an @handle or a channel ID.")) }

        if isChannelID(trimmed) { return trimmed }
        if let match = trimmed.firstMatch(of: #/\/channel\/(UC[A-Za-z0-9_-]{22})/#) {
            return String(match.1)
        }

        let url = try pageURL(for: trimmed)
        if let id = try? await scrape(url) { return id }
        if let id = try? await YTDLPManager.shared.channelID(for: url.absoluteString) { return id }
        throw AppError(String(localized: "Channel not found. Tip: copy the channel URL from your browser."))
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
            throw AppError(String(localized: "That doesn’t look like a YouTube address."))
        }
        return url
    }

    /// Loads a YouTube page as HTML (bypassing the EU cookie consent page).
    nonisolated static func fetchPage(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.httpShouldHandleCookies = false
        // Bypasses the EU cookie consent page.
        request.setValue("SOCS=CAI; CONSENT=YES+cb", forHTTPHeaderField: "Cookie")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw AppError(String(localized: "Page not reachable (HTTP \(http.statusCode))."))
        }
        guard let html = String(data: data, encoding: .utf8) else { throw AppError(String(localized: "The page could not be read.")) }
        return html
    }

    private static func scrape(_ url: URL) async throws -> String? {
        let html = try await fetchPage(url)

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
