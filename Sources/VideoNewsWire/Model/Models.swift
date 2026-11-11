import Foundation

/// A subscribed YouTube channel.
struct Channel: Codable, Identifiable, Hashable {
    let id: String              // UC…
    var title: String
    var lastRefreshed: Date? = nil
    var lastError: String? = nil
    /// Folder the channel is filed in (`nil` = no folder).
    var folderID: UUID? = nil
    /// When the channel avatar was last fetched.
    var avatarUpdated: Date? = nil

    var feedURL: URL {
        URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(id)")!
    }

    var pageURL: URL {
        URL(string: "https://www.youtube.com/channel/\(id)")!
    }
}

/// Folder for grouping subscriptions (e.g. "Food", "Tech").
struct Folder: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var isExpanded = true
}

/// A video from a channel's RSS feed.
struct Video: Codable, Identifiable, Hashable {
    let id: String              // YouTube video ID
    var channelID: String
    var channelTitle: String
    var title: String
    var published: Date
    var descriptionText: String
    var isShort: Bool

    var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }
    var thumbnailURL: URL? { URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg") }
}

/// Local state of a video (watched, saved, downloaded, AI summary).
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
        case .unwatched: String(localized: "New")
        case .today: String(localized: "Today")
        case .saved: String(localized: "Watch Later")
        case .downloaded: String(localized: "Downloads")
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
    case folder(UUID)
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

/// Keys for UserDefaults / @AppStorage.
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
            showThumbnails: false,      // thumbnails are optimized for clicks – off by default
            showUnreadCounts: false,    // no red counters urging you to clear a backlog
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
