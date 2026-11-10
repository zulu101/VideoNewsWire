import Foundation

/// Ein abonnierter YouTube-Kanal.
struct Channel: Codable, Identifiable, Hashable {
    let id: String              // UC…
    var title: String
    var lastRefreshed: Date? = nil
    var lastError: String? = nil

    var feedURL: URL {
        URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(id)")!
    }
}

/// Ein Video aus dem RSS-Feed eines Kanals.
struct Video: Codable, Identifiable, Hashable {
    let id: String              // YouTube-Video-ID
    var channelID: String
    var channelTitle: String
    var title: String
    var published: Date
    var descriptionText: String
    var isShort: Bool

    var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }
    var thumbnailURL: URL? { URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg") }
}

/// Lokaler Zustand eines Videos (gesehen, gemerkt, heruntergeladen, KI-Zusammenfassung).
struct VideoState: Codable, Hashable {
    var watched = false
    var saved = false
    var localFile: String?
    var aiSummary: String?
}

enum SmartFeed: String, CaseIterable, Hashable {
    case unwatched, today, saved, downloaded

    var title: String {
        switch self {
        case .unwatched: "Neu"
        case .today: "Heute"
        case .saved: "Merkliste"
        case .downloaded: "Downloads"
        }
    }

    var systemImage: String {
        switch self {
        case .unwatched: "circle.inset.filled"
        case .today: "sun.max"
        case .saved: "bookmark"
        case .downloaded: "arrow.down.circle"
        }
    }
}

enum SidebarSelection: Hashable {
    case smart(SmartFeed)
    case channel(String)
}

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum AppPaths {
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("VideoNewsWire", isDirectory: true)
    }
}

/// Schlüssel für UserDefaults / @AppStorage.
enum Prefs {
    static let hideShorts = "hideShorts"
    static let showThumbnails = "showThumbnails"
    static let showUnreadCounts = "showUnreadCounts"
    static let markWatchedOnOpen = "markWatchedOnOpen"
    static let downloadFolder = "downloadFolder"
    static let maxDownloadHeight = "maxDownloadHeight"
    static let autoUpdateYTDLP = "autoUpdateYTDLP"
    static let ytdlpLastUpdate = "ytdlpLastUpdate"
    static let cookieBrowser = "cookieBrowser"
    static let lastRefresh = "lastRefresh"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            hideShorts: true,
            showThumbnails: false,      // Thumbnails sind auf Klicks optimiert – standardmäßig aus
            showUnreadCounts: false,    // keine roten Zähler, die zum Abarbeiten drängen
            markWatchedOnOpen: true,
            maxDownloadHeight: 1080,
            autoUpdateYTDLP: true,
            cookieBrowser: "safari",
        ])
    }

    static var downloadFolderURL: URL {
        if let path = UserDefaults.standard.string(forKey: downloadFolder), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        return downloads.appendingPathComponent("VideoNewsWire", isDirectory: true)
    }
}
