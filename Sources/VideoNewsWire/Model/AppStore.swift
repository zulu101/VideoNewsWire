import AppKit
import Foundation
import Observation

/// Zentrale Datenhaltung: Abos, Videos und deren Zustand. Wird als JSON gespeichert.
@MainActor @Observable
final class AppStore {
    static let shared = AppStore()

    private(set) var channels: [Channel] = []
    private(set) var folders: [Folder] = []
    /// Lokal gespeicherte Kanalbilder (Kanal-ID → Bild).
    private(set) var avatars: [String: NSImage] = AvatarService.loadAll()
    private(set) var videos: [String: Video] = [:]
    private(set) var states: [String: VideoState] = [:]

    private(set) var isRefreshing = false
    private(set) var refreshDone = 0
    private(set) var refreshTotal = 0
    private(set) var lastRefresh: Date? = UserDefaults.standard.object(forKey: Prefs.lastRefresh) as? Date

    var showingAddChannel = false
    var showingNewFolder = false
    var errorMessage: String?

    private struct Library: Codable {
        var channels: [Channel]
        var folders: [Folder]?   // optional: ältere Bibliotheken haben noch keine Ordner
        var videos: [Video]
        var states: [String: VideoState]
    }

    @ObservationIgnored private let libraryURL = AppPaths.support.appendingPathComponent("library.json")

    init() {
        load()
    }

    // MARK: Persistenz

    private func load() {
        guard let data = try? Data(contentsOf: libraryURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let library = try? decoder.decode(Library.self, from: data) else { return }
        channels = library.channels
        folders = library.folders ?? []
        videos = Dictionary(library.videos.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        states = library.states
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let library = Library(channels: channels, folders: folders, videos: Array(videos.values), states: states)
        do {
            try FileManager.default.createDirectory(at: libraryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(library).write(to: libraryURL, options: .atomic)
        } catch {
            errorMessage = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    // MARK: Abfragen

    func state(_ videoID: String) -> VideoState {
        states[videoID] ?? VideoState()
    }

    func update(_ videoID: String, _ change: (inout VideoState) -> Void) {
        var state = state(videoID)
        change(&state)
        states[videoID] = state
        save()
    }

    func markWatched(_ ids: [String], watched: Bool = true) {
        for id in ids { states[id, default: VideoState()].watched = watched }
        save()
    }

    func localFileURL(for videoID: String) -> URL? {
        guard let path = state(videoID).localFile, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Videos für die Seitenleisten-Auswahl. `keeping` hält das gerade geöffnete Video in der Liste,
    /// auch wenn es durch das Öffnen als gesehen markiert wurde (wie in NetNewsWire).
    func videos(for selection: SidebarSelection, hideShorts: Bool, keeping keepID: String? = nil) -> [Video] {
        var list = videos.values.filter { !hideShorts || !$0.isShort || $0.id == keepID }
        switch selection {
        case .smart(.unwatched):
            list = list.filter { !state($0.id).watched || $0.id == keepID }
        case .smart(.today):
            let start = Calendar.current.startOfDay(for: Date())
            list = list.filter { $0.published >= start }
        case .smart(.saved):
            list = list.filter { state($0.id).saved }
        case .smart(.downloaded):
            list = list.filter { state($0.id).localFile != nil }
        case .folder(let folderID):
            let ids = Set(channels.filter { $0.folderID == folderID }.map(\.id))
            list = list.filter { ids.contains($0.channelID) }
        case .channel(let id):
            list = list.filter { $0.channelID == id }
        }
        return list.sorted { $0.published > $1.published }
    }

    func unwatchedCount(_ selection: SidebarSelection, hideShorts: Bool) -> Int {
        videos(for: selection, hideShorts: hideShorts).filter { !state($0.id).watched }.count
    }

    func channel(_ id: String) -> Channel? {
        channels.first { $0.id == id }
    }

    // MARK: Aktualisieren

    func refreshAll() async {
        guard !isRefreshing, !channels.isEmpty else { return }
        isRefreshing = true
        let ids = channels.map(\.id)
        refreshDone = 0
        refreshTotal = ids.count

        await withTaskGroup(of: (String, Result<FeedService.Feed, Error>).self) { group in
            var iterator = ids.makeIterator()
            // Höchstens 6 gleichzeitige Anfragen.
            for _ in 0..<min(6, ids.count) {
                if let id = iterator.next() {
                    group.addTask { (id, await FeedService.fetchResult(channelID: id)) }
                }
            }
            while let finished = await group.next() {
                apply(finished.0, finished.1)
                refreshDone += 1
                if let nextID = iterator.next() {
                    group.addTask { (nextID, await FeedService.fetchResult(channelID: nextID)) }
                }
            }
        }

        lastRefresh = Date()
        UserDefaults.standard.set(lastRefresh, forKey: Prefs.lastRefresh)
        isRefreshing = false
        save()
        await refreshAvatars()
    }

    // MARK: Kanalbilder

    /// Lädt fehlende Kanalbilder und erneuert sie alle 30 Tage.
    func refreshAvatars() async {
        let maxAge: TimeInterval = 30 * 24 * 3600
        let due = channels
            .filter { avatars[$0.id] == nil || Date().timeIntervalSince($0.avatarUpdated ?? .distantPast) > maxAge }
            .map(\.id)
        guard !due.isEmpty else { return }

        await withTaskGroup(of: (String, Data?).self) { group in
            var iterator = due.makeIterator()
            for _ in 0..<min(4, due.count) {
                if let id = iterator.next() {
                    group.addTask { (id, try? await AvatarService.download(channelID: id)) }
                }
            }
            while let finished = await group.next() {
                let (id, data) = finished
                if let data, let image = NSImage(data: data),
                   let index = channels.firstIndex(where: { $0.id == id }) {
                    avatars[id] = image
                    channels[index].avatarUpdated = Date()
                }
                if let nextID = iterator.next() {
                    group.addTask { (nextID, try? await AvatarService.download(channelID: nextID)) }
                }
            }
        }
        save()
    }

    private func apply(_ channelID: String, _ result: Result<FeedService.Feed, Error>) {
        guard let index = channels.firstIndex(where: { $0.id == channelID }) else { return }
        switch result {
        case .success(let feed):
            let firstFetch = channels[index].lastRefreshed == nil
            if !feed.channelTitle.isEmpty { channels[index].title = feed.channelTitle }
            channels[index].lastRefreshed = Date()
            channels[index].lastError = nil
            merge(feed.videos, initialFetch: firstFetch)
        case .failure(let error):
            channels[index].lastError = error.localizedDescription
        }
    }

    /// Beim ersten Abruf eines neuen Kanals werden ältere Videos (> 7 Tage) direkt als gesehen
    /// markiert – sonst würde „Neu“ mit dem halben Backkatalog geflutet.
    private func merge(_ newVideos: [Video], initialFetch: Bool) {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        for video in newVideos {
            let isNew = videos[video.id] == nil
            videos[video.id] = video
            if isNew && initialFetch && video.published < cutoff && states[video.id] == nil {
                states[video.id] = VideoState(watched: true)
            }
        }
    }

    // MARK: Kanäle verwalten

    @discardableResult
    func addChannel(_ input: String) async throws -> Channel {
        let id = try await ChannelResolver.resolve(input)
        if let existing = channel(id) { return existing }
        let feed = try await FeedService.fetch(channelID: id)
        let channel = Channel(id: id, title: feed.channelTitle.isEmpty ? id : feed.channelTitle, lastRefreshed: Date())
        channels.append(channel)
        merge(feed.videos, initialFetch: true)
        save()
        Task { await refreshAvatars() }
        return channel
    }

    /// Fügt mehrere Kanäle hinzu (Import) und lädt danach alle Feeds. Liefert die Anzahl neuer Kanäle.
    @discardableResult
    func importChannels(_ list: [(id: String, title: String)]) async -> Int {
        var added = 0
        for item in list where channel(item.id) == nil {
            channels.append(Channel(id: item.id, title: item.title))
            added += 1
        }
        guard added > 0 else { return 0 }
        save()
        await refreshAll()
        return added
    }

    /// Import der `subscriptions.csv` aus Google Takeout (Spalten: Kanal-ID, Kanal-URL, Kanaltitel).
    func importTakeoutCSV(from url: URL) async throws -> Int {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let text = try String(contentsOf: url, encoding: .utf8)
        var found: [(id: String, title: String)] = []
        for line in text.components(separatedBy: .newlines) {
            let fields = CSV.fields(line)
            guard let id = fields.first(where: ChannelResolver.isChannelID) else { continue }
            let title = fields.last.flatMap { $0.isEmpty ? nil : $0 } ?? id
            found.append((id, title))
        }
        guard !found.isEmpty else { throw AppError("In der Datei wurden keine Kanäle gefunden.") }
        return await importChannels(found)
    }

    func removeChannel(_ id: String) {
        channels.removeAll { $0.id == id }
        avatars[id] = nil
        AvatarService.delete(channelID: id)
        // Gemerkte und heruntergeladene Videos bleiben erhalten.
        for video in videos.values where video.channelID == id {
            let state = state(video.id)
            if !state.saved && state.localFile == nil {
                videos[video.id] = nil
                states[video.id] = nil
            }
        }
        save()
    }

    // MARK: Ordner

    func channels(inFolder folderID: UUID?) -> [Channel] {
        channels.filter { $0.folderID == folderID }
    }

    @discardableResult
    func createFolder(named name: String) -> Folder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = folders.first(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        let folder = Folder(name: trimmed)
        folders.append(folder)
        save()
        return folder
    }

    func renameFolder(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].name = trimmed
        save()
    }

    /// Löscht den Ordner; die enthaltenen Kanäle bleiben abonniert (ohne Ordner).
    func deleteFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        for index in channels.indices where channels[index].folderID == id {
            channels[index].folderID = nil
        }
        save()
    }

    func setFolder(_ id: UUID, expanded: Bool) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].isExpanded = expanded
        save()
    }

    // MARK: Reihenfolge
    //
    // Die Reihenfolge in der Seitenleiste entspricht der Reihenfolge der Arrays `channels`
    // und `folders` – sie wird nur noch durch den Nutzer verändert (Drag & Drop, Menü).

    /// Verschiebt einen Kanal in einen Ordner (`nil` = ohne Ordner) – ans Ende oder an den Anfang.
    func moveChannel(_ channelID: String, toFolder folderID: UUID?, atTop: Bool = false) {
        guard let index = channels.firstIndex(where: { $0.id == channelID }) else { return }
        var channel = channels.remove(at: index)
        channel.folderID = folderID
        if atTop, let first = channels.firstIndex(where: { $0.folderID == folderID }) {
            channels.insert(channel, at: first)
        } else if !atTop, let last = channels.lastIndex(where: { $0.folderID == folderID }) {
            channels.insert(channel, at: last + 1)
        } else {
            channels.insert(channel, at: atTop ? 0 : channels.count)
        }
        save()
    }

    /// Setzt einen Kanal an die Stelle eines anderen (übernimmt dessen Ordner).
    /// Nach unten gezogen landet er hinter dem Ziel, nach oben gezogen davor.
    func moveChannel(_ channelID: String, onto targetID: String) {
        guard channelID != targetID,
              let from = channels.firstIndex(where: { $0.id == channelID }),
              let to = channels.firstIndex(where: { $0.id == targetID }) else { return }
        let target = channels[to]
        let movingDown = channels[from].folderID == target.folderID && from < to
        var channel = channels.remove(at: from)
        channel.folderID = target.folderID
        guard let newTo = channels.firstIndex(where: { $0.id == targetID }) else { return }
        channels.insert(channel, at: movingDown ? newTo + 1 : newTo)
        save()
    }

    /// Verschiebt einen Kanal innerhalb seiner Gruppe um eine Position nach oben (-1) oder unten (+1).
    func nudgeChannel(_ channelID: String, by offset: Int) {
        guard let channel = channel(channelID) else { return }
        let group = channels(inFolder: channel.folderID)
        guard let position = group.firstIndex(where: { $0.id == channelID }),
              group.indices.contains(position + offset) else { return }
        moveChannel(channelID, onto: group[position + offset].id)
    }

    /// Setzt einen Ordner an die Stelle eines anderen.
    func moveFolder(_ folderID: UUID, onto targetID: UUID) {
        guard folderID != targetID,
              let from = folders.firstIndex(where: { $0.id == folderID }),
              let to = folders.firstIndex(where: { $0.id == targetID }) else { return }
        // Nach unten gezogen landet der Ordner hinter dem Ziel, nach oben gezogen davor.
        let folder = folders.remove(at: from)
        folders.insert(folder, at: to)
        save()
    }

    func nudgeFolder(_ folderID: UUID, by offset: Int) {
        guard let position = folders.firstIndex(where: { $0.id == folderID }),
              folders.indices.contains(position + offset) else { return }
        folders.swapAt(position, position + offset)
        save()
    }

    func moveFolderToTop(_ folderID: UUID) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders.insert(folders.remove(at: index), at: 0)
        save()
    }

    /// Einmalig alphabetisch sortieren (Ordner, und Kanäle innerhalb jeder Gruppe).
    func sortAlphabetically() {
        folders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        channels.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        save()
    }

    func folder(_ id: UUID) -> Folder? {
        folders.first { $0.id == id }
    }


    // MARK: Downloads

    func download(_ video: Video) {
        Task {
            do {
                let height = UserDefaults.standard.integer(forKey: Prefs.maxDownloadHeight)
                let url = try await YTDLPManager.shared.download(video, to: Prefs.downloadFolderURL,
                                                                 maxHeight: height > 0 ? height : 1080)
                update(video.id) { $0.localFile = url.path }
            } catch is CancellationError {
            } catch {
                errorMessage = "Download fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    func deleteDownload(_ videoID: String) {
        if let url = localFileURL(for: videoID) {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        update(videoID) { $0.localFile = nil }
    }
}

enum CSV {
    /// Einfacher CSV-Zeilen-Parser mit Unterstützung für Anführungszeichen.
    static func fields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(line)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == "\"" {
                if inQuotes && index + 1 < chars.count && chars[index + 1] == "\"" {
                    current.append("\"")
                    index += 1
                } else {
                    inQuotes.toggle()
                }
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
            index += 1
        }
        fields.append(current)
        return fields.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
