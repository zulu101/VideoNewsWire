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
        .searchable(text: $searchText, prompt: "Title, description, channel")
        .toolbar {
            ToolbarItem {
                Button("Mark All as Watched", systemImage: "checkmark.circle") {
                    store.markWatched(items.map(\.id))
                }
                .disabled(items.isEmpty)
                .help("Mark all videos in this list as watched")
            }
        }
    }

    private var filteredVideos: [Video] {
        let list = store.videos(for: selection, hideShorts: hideShorts, keeping: selectedVideoID)
        // With several search terms, all must match (in title, channel, description or AI summary).
        let terms = searchText.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return list }
        return list.filter { video in
            let summary = store.state(video.id).aiSummary ?? ""
            return terms.allSatisfy { term in
                video.title.localizedStandardContains(term)
                    || video.channelTitle.localizedStandardContains(term)
                    || video.descriptionText.localizedStandardContains(term)
                    || summary.localizedStandardContains(term)
            }
        }
    }

    private var isChannelSelection: Bool {
        if case .channel = selection { return true }
        return false
    }

    private var title: String {
        switch selection {
        case .smart(let feed): feed.title
        case .folder(let id): store.folder(id)?.name ?? String(localized: "Folder")
        case .channel(let id): store.channel(id)?.title ?? String(localized: "Channel")
        }
    }

    @ViewBuilder private var emptyState: some View {
        if store.channels.isEmpty {
            ContentUnavailableView {
                Label("No Subscriptions Yet", systemImage: "person.crop.square.badge.plus")
            } description: {
                Text("Add channels or import your YouTube subscriptions.")
            } actions: {
                Button("Add Channel…") { store.showingAddChannel = true }
            }
        } else if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if selection == .smart(.unwatched) {
            ContentUnavailableView("All Caught Up", systemImage: "checkmark.circle",
                                   description: Text("No new videos. Time for something else."))
        } else {
            ContentUnavailableView("No Videos", systemImage: "tray")
        }
    }

    @ViewBuilder private func contextMenu(for video: Video) -> some View {
        let state = store.state(video.id)
        Button(state.watched ? String(localized: "Mark as New") : String(localized: "Mark as Watched")) {
            store.update(video.id) { $0.watched.toggle() }
        }
        Button(state.saved ? String(localized: "Remove from Watch Later") : String(localized: "Save for Later")) {
            store.update(video.id) { $0.saved.toggle() }
        }
        Divider()
        if let file = store.localFileURL(for: video.id) {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
            Button("Delete Download", role: .destructive) { store.deleteDownload(video.id) }
        } else {
            Button("Download") { store.download(video) }
        }
        Divider()
        Button("Copy Link") {
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
                        ChannelIcon(channelID: video.channelID, size: 12)
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
