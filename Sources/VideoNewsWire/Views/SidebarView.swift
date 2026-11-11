import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(AppStore.self) private var store
    @Binding var selection: SidebarSelection?
    @AppStorage(Prefs.showUnreadCounts) private var showCounts = false
    @AppStorage(Prefs.hideShorts) private var hideShorts = true

    @State private var prompt: FolderPrompt?
    @State private var folderName = ""
    /// Folder currently being dragged (only used to show the insertion line).
    @State private var draggedFolderID: UUID?

    /// Payload of a drag in the sidebar: channel or folder.
    enum DragItem {
        case channel(String)
        case folder(UUID)

        init?(_ string: String) {
            if string.hasPrefix("folder:") {
                guard let id = UUID(uuidString: String(string.dropFirst(7))) else { return nil }
                self = .folder(id)
            } else {
                let id = string.hasPrefix("channel:") ? String(string.dropFirst(8)) : string
                guard ChannelResolver.isChannelID(id) else { return nil }
                self = .channel(id)
            }
        }
    }

    /// Input dialog for creating or renaming a folder.
    enum FolderPrompt: Identifiable {
        case create(moveChannelID: String?)
        case rename(UUID)

        var id: String {
            switch self {
            case .create(let channelID): "create-\(channelID ?? "")"
            case .rename(let id): "rename-\(id)"
            }
        }
    }

    var body: some View {
        List(selection: $selection) {
            Section("Overview") {
                ForEach(SmartFeed.allCases, id: \.self) { feed in
                    Label(feed.title, systemImage: feed.systemImage)
                        .badge(count(.smart(feed)))
                        .tag(SidebarSelection.smart(feed))
                }
            }

            Section {
                ForEach(store.folders) { folder in
                    DisclosureGroup(isExpanded: expandedBinding(for: folder)) {
                        ForEach(store.channels(inFolder: folder.id)) { channel in
                            channelRow(channel)
                        }
                        // Insertion line between this folder's channels.
                        .dropDestination(for: String.self) { items, index in
                            insertChannels(items, folder: folder.id, at: index)
                        }
                    } label: {
                        FolderLabel(
                            folder: folder,
                            badge: count(.folder(folder.id)),
                            isFolderDrag: { draggedFolderID != nil },
                            onDragStart: { draggedFolderID = folder.id },
                            onDrop: { payload, zone in handleFolderDrop(payload, zone: zone, target: folder.id) }
                        )
                        .tag(SidebarSelection.folder(folder.id))
                        .contextMenu { folderMenu(folder) }
                    }
                }
                // Deliberately NO indexed `.dropDestination(for:action:)` on this ForEach:
                // SwiftUI crashes on insertion drops between disclosure groups
                // (OutlineListCoordinator.performDropInsertion). Folders are reordered
                // through FolderLabel with its own insertion line instead.

                ForEach(store.channels(inFolder: nil)) { channel in
                    channelRow(channel)
                }
                // Insertion line between channels without a folder.
                .dropDestination(for: String.self) { items, index in
                    insertChannels(items, folder: nil, at: index)
                }
            } header: {
                Text("Subscriptions")
            }
        }
        .listStyle(.sidebar)
        .contextMenu {
            Button("New Folder…") { askForNewFolder() }
            Button("Sort Alphabetically") { store.sortAlphabetically() }
        }
        .safeAreaInset(edge: .bottom) {
            statusLine
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .alert(promptTitle, isPresented: Binding(
            get: { prompt != nil },
            set: { if !$0 { prompt = nil } }
        ), presenting: prompt) { prompt in
            TextField("Name", text: $folderName)
            Button(promptButtonTitle(prompt)) { commit(prompt) }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: store.showingNewFolder) { _, show in
            if show {
                askForNewFolder()
                store.showingNewFolder = false
            }
        }
    }

    // MARK: Rows

    private func channelRow(_ channel: Channel) -> some View {
        Label {
            HStack {
                Text(channel.title).lineLimit(1)
                if let error = channel.lastError {
                    Spacer(minLength: 0)
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .help(error)
                }
            }
        } icon: {
            ChannelIcon(channelID: channel.id, size: 18)
        }
        .badge(count(.channel(channel.id)))
        .tag(SidebarSelection.channel(channel.id))
        .draggable("channel:\(channel.id)")
        .contextMenu { channelMenu(channel) }
    }

    @ViewBuilder private func channelMenu(_ channel: Channel) -> some View {
        Menu("Move to Folder") {
            ForEach(store.folders) { folder in
                Button(folder.name) { store.moveChannel(channel.id, toFolder: folder.id) }
                    .disabled(channel.folderID == folder.id)
            }
            if channel.folderID != nil {
                Divider()
                Button("Remove from Folder") { store.moveChannel(channel.id, toFolder: nil) }
            }
            Divider()
            Button("New Folder…") { askForNewFolder(moving: channel.id) }
        }
        Button("Move Up") { store.nudgeChannel(channel.id, by: -1) }
        Button("Move Down") { store.nudgeChannel(channel.id, by: 1) }
        Button("Mark All as Watched") {
            store.markWatched(store.videos(for: .channel(channel.id), hideShorts: false).map(\.id))
        }
        Divider()
        Button("Unsubscribe", role: .destructive) {
            if selection == .channel(channel.id) { selection = .smart(.unwatched) }
            store.removeChannel(channel.id)
        }
    }

    @ViewBuilder private func folderMenu(_ folder: Folder) -> some View {
        Button("Rename…") {
            folderName = folder.name
            prompt = .rename(folder.id)
        }
        Button("Mark All as Watched") {
            store.markWatched(store.videos(for: .folder(folder.id), hideShorts: false).map(\.id))
        }
        Button("Move Up") { store.nudgeFolder(folder.id, by: -1) }
        Button("Move Down") { store.nudgeFolder(folder.id, by: 1) }
        Divider()
        Button("New Folder…") { askForNewFolder() }
        Button("Delete Folder (Keeps Subscriptions)", role: .destructive) {
            if selection == .folder(folder.id) { selection = .smart(.unwatched) }
            store.deleteFolder(folder.id)
        }
    }

    @ViewBuilder private var statusLine: some View {
        if store.isRefreshing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Updating \(store.refreshDone)/\(store.refreshTotal)…")
            }
        } else if let last = store.lastRefresh {
            Text("Updated \(last, format: .relative(presentation: .named))")
        }
    }

    // MARK: Helpers

    private func count(_ selection: SidebarSelection) -> Int {
        showCounts ? store.unwatchedCount(selection, hideShorts: hideShorts) : 0
    }

    private func expandedBinding(for folder: Folder) -> Binding<Bool> {
        Binding(
            get: { store.folder(folder.id)?.isExpanded ?? true },
            set: { store.setFolder(folder.id, expanded: $0) }
        )
    }

    // MARK: Drag & Drop

    /// Drops channels at the insertion line (position `index` within the group).
    private func insertChannels(_ items: [String], folder: UUID?, at index: Int) {
        draggedFolderID = nil
        var position = index
        for case .channel(let id) in items.compactMap(DragItem.init) where store.channel(id) != nil {
            store.moveChannel(id, toFolder: folder, at: position)
            position += 1
        }
    }

    /// Drop on a folder name: put a folder before/after it, move a channel into it.
    private func handleFolderDrop(_ payload: String, zone: FolderDropZone, target: UUID) {
        draggedFolderID = nil
        switch DragItem(payload) {
        case .folder(let id)?:
            guard let index = store.folders.firstIndex(where: { $0.id == target }) else { return }
            store.moveFolder(id, to: zone == .below ? index + 1 : index)
        case .channel(let id)? where store.channel(id) != nil:
            store.moveChannel(id, toFolder: target)
        default:
            break
        }
    }

    private func askForNewFolder(moving channelID: String? = nil) {
        folderName = ""
        prompt = .create(moveChannelID: channelID)
    }

    private var promptTitle: String {
        if case .rename = prompt { return String(localized: "Rename Folder") }
        return String(localized: "New Folder")
    }

    private func promptButtonTitle(_ prompt: FolderPrompt) -> String {
        if case .rename = prompt { return String(localized: "Rename") }
        return String(localized: "Create")
    }

    private func commit(_ prompt: FolderPrompt) {
        switch prompt {
        case .create(let channelID):
            if let folder = store.createFolder(named: folderName), let channelID {
                store.moveChannel(channelID, toFolder: folder.id)
            }
        case .rename(let id):
            store.renameFolder(id, to: folderName)
        }
    }
}

/// Round channel avatar; a placeholder until one is loaded.
struct ChannelIcon: View {
    @Environment(AppStore.self) private var store
    let channelID: String
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let image = store.avatars[channelID] {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - Folder row with its own drop logic

enum FolderDropZone {
    case none, above, inside, below
}

/// Folder name in the sidebar. When a folder is dragged, a line above or below shows where it
/// will land; when a channel is dragged, the folder is highlighted (drop into it).
private struct FolderLabel: View {
    let folder: Folder
    let badge: Int
    let isFolderDrag: () -> Bool
    let onDragStart: () -> Void
    let onDrop: (String, FolderDropZone) -> Void

    @State private var zone: FolderDropZone = .none
    @State private var height: CGFloat = 24

    var body: some View {
        Label(folder.name, systemImage: "folder")
            .badge(badge)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .onDrag {
                onDragStart()
                return NSItemProvider(object: "folder:\(folder.id.uuidString)" as NSString)
            }
            .onDrop(of: [.plainText, .utf8PlainText, .text], delegate: FolderDropDelegate(
                height: height, isFolderDrag: isFolderDrag, zone: $zone, perform: onDrop
            ))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(zone == .inside ? 0.22 : 0))
                    .padding(.horizontal, -4)
            )
            .overlay(alignment: zone == .below ? .bottom : .top) {
                if zone == .above || zone == .below {
                    InsertionLine()
                        .offset(y: zone == .above ? -3 : 3)
                }
            }
    }
}

/// macOS-style insertion line: circle on the left, solid line in the accent color.
private struct InsertionLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .frame(width: 7, height: 7)
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
        }
        .frame(height: 7)
        .allowsHitTesting(false)
    }
}

private struct FolderDropDelegate: DropDelegate {
    let height: CGFloat
    let isFolderDrag: () -> Bool
    @Binding var zone: FolderDropZone
    let perform: (String, FolderDropZone) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText, .utf8PlainText, .text])
    }

    func dropEntered(info: DropInfo) {
        update(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        zone = .none
    }

    func performDrop(info: DropInfo) -> Bool {
        let finalZone = zone
        zone = .none
        guard let provider = info.itemProviders(for: [.plainText, .utf8PlainText, .text]).first else { return false }
        _ = provider.loadTransferable(type: String.self) { result in
            guard case .success(let payload) = result else { return }
            DispatchQueue.main.async { perform(payload, finalZone) }
        }
        return true
    }

    /// Folder: upper half = before, lower half = after. Channel: into the folder.
    private func update(_ info: DropInfo) {
        if isFolderDrag() {
            zone = info.location.y < height / 2 ? .above : .below
        } else {
            zone = .inside
        }
    }
}
