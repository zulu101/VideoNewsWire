import AppKit
import SwiftUI

struct VideoListView: View {
    @Environment(AppStore.self) private var store
    let selection: SidebarSelection
    @Binding var selectedVideoID: String?

    @AppStorage(Prefs.hideShorts) private var hideShorts = true
    @AppStorage(Prefs.showThumbnails) private var showThumbnails = false
    @State private var searchText = ""

    var body: some View {
        let items = filteredVideos

        List(items, selection: $selectedVideoID) { video in
            VideoRow(video: video,
                     state: store.state(video.id),
                     showThumbnail: showThumbnails,
                     showChannel: !isChannelSelection)
                .contextMenu { contextMenu(for: video) }
        }
        .overlay {
            if items.isEmpty { emptyState }
        }
        .navigationTitle(title)
        .searchable(text: $searchText, prompt: "Titel durchsuchen")
        .toolbar {
            ToolbarItem {
                Button("Alle als gesehen markieren", systemImage: "checkmark.circle") {
                    store.markWatched(items.map(\.id))
                }
                .disabled(items.isEmpty)
                .help("Alle Videos in dieser Liste als gesehen markieren")
            }
        }
    }

    private var filteredVideos: [Video] {
        let list = store.videos(for: selection, hideShorts: hideShorts, keeping: selectedVideoID)
        guard !searchText.isEmpty else { return list }
        return list.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.channelTitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var isChannelSelection: Bool {
        if case .channel = selection { return true }
        return false
    }

    private var title: String {
        switch selection {
        case .smart(let feed): feed.title
        case .channel(let id): store.channel(id)?.title ?? "Kanal"
        }
    }

    @ViewBuilder private var emptyState: some View {
        if store.channels.isEmpty {
            ContentUnavailableView {
                Label("Noch keine Abos", systemImage: "person.crop.square.badge.plus")
            } description: {
                Text("Füge Kanäle hinzu oder importiere deine YouTube-Abos.")
            } actions: {
                Button("Kanal hinzufügen…") { store.showingAddChannel = true }
            }
        } else if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if selection == .smart(.unwatched) {
            ContentUnavailableView("Alles gesehen", systemImage: "checkmark.circle",
                                   description: Text("Keine neuen Videos. Zeit für etwas anderes."))
        } else {
            ContentUnavailableView("Keine Videos", systemImage: "tray")
        }
    }

    @ViewBuilder private func contextMenu(for video: Video) -> some View {
        let state = store.state(video.id)
        Button(state.watched ? "Als neu markieren" : "Als gesehen markieren") {
            store.update(video.id) { $0.watched.toggle() }
        }
        Button(state.saved ? "Von Merkliste entfernen" : "Merken") {
            store.update(video.id) { $0.saved.toggle() }
        }
        Divider()
        if let file = store.localFileURL(for: video.id) {
            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
            Button("Download löschen", role: .destructive) { store.deleteDownload(video.id) }
        } else {
            Button("Herunterladen") { store.download(video) }
        }
        Divider()
        Button("Link kopieren") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(video.watchURL.absoluteString, forType: .string)
        }
    }
}

struct VideoRow: View {
    let video: Video
    let state: VideoState
    let showThumbnail: Bool
    let showChannel: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(state.watched ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            if showThumbnail {
                AsyncImage(url: video.thumbnailURL) { image in
                    image.resizable().aspectRatio(16 / 9, contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(width: 96, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(video.title)
                    .fontWeight(state.watched ? .regular : .semibold)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if showChannel {
                        Text(video.channelTitle)
                        Text("·")
                    }
                    Text(video.published, format: .relative(presentation: .named))
                    Spacer(minLength: 0)
                    if video.isShort { Image(systemName: "rectangle.portrait").help("Short") }
                    if state.saved { Image(systemName: "bookmark.fill") }
                    if state.localFile != nil { Image(systemName: "arrow.down.circle.fill") }
                    if state.aiSummary != nil { Image(systemName: "sparkles") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}
