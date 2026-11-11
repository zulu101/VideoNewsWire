import Foundation

/// Loads YouTube channels' public RSS feeds (no API key, no sign-in needed).
enum FeedService {
    struct Feed {
        var channelTitle: String
        var videos: [Video]
    }

    static func fetch(channelID: String) async throws -> Feed {
        var request = URLRequest(url: URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelID)")!)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw AppError(String(localized: "Feed not reachable (HTTP \(http.statusCode))."))
        }
        let parser = FeedParser(channelID: channelID)
        try parser.parse(data)
        return Feed(channelTitle: parser.channelTitle, videos: parser.videos)
    }

    static func fetchResult(channelID: String) async -> Result<Feed, Error> {
        do { return .success(try await fetch(channelID: channelID)) } catch { return .failure(error) }
    }
}

/// Minimal Atom parser for `https://www.youtube.com/feeds/videos.xml`.
final class FeedParser: NSObject, XMLParserDelegate {
    private let channelID: String
    private(set) var channelTitle = ""
    private(set) var videos: [Video] = []

    private var inEntry = false
    private var inAuthor = false
    private var text = ""

    private var vID = ""
    private var vTitle = ""
    private var vPublished = ""
    private var vDescription = ""
    private var vLink = ""
    private var vAuthor = ""

    private let dateFormatter = ISO8601DateFormatter()

    init(channelID: String) {
        self.channelID = channelID
    }

    func parse(_ data: Data) throws {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? AppError(String(localized: "The feed could not be read."))
        }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch elementName {
        case "entry":
            inEntry = true
            vID = ""; vTitle = ""; vPublished = ""; vDescription = ""; vLink = ""; vAuthor = ""
        case "author":
            inAuthor = true
        case "link" where inEntry && attributes["rel"] == "alternate":
            vLink = attributes["href"] ?? ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "yt:videoId" where inEntry:
            vID = value
        case "title":
            if inEntry { vTitle = value } else if channelTitle.isEmpty { channelTitle = value }
        case "name" where inAuthor:
            if inEntry { vAuthor = value } else { channelTitle = value }
        case "published" where inEntry:
            vPublished = value
        case "media:description" where inEntry:
            vDescription = value
        case "author":
            inAuthor = false
        case "entry":
            inEntry = false
            if !vID.isEmpty {
                videos.append(Video(
                    id: vID,
                    channelID: channelID,
                    channelTitle: vAuthor.isEmpty ? channelTitle : vAuthor,
                    title: vTitle,
                    published: dateFormatter.date(from: vPublished) ?? Date(),
                    descriptionText: vDescription,
                    isShort: vLink.contains("/shorts/")
                ))
            }
        default:
            break
        }
        text = ""
    }
}
