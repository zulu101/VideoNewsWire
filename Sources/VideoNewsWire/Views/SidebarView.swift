import SwiftUI

struct SidebarView: View {
    @Environment(AppStore.self) private var store
    @Binding var selection: SidebarSelection?
    @AppStorage(Prefs.showUnreadCounts) private var showCounts = false
    @AppStorage(Prefs.hideShorts) private var hideShorts = true

    @State private var prompt: FolderPrompt?
    @State private var folderName = ""
    /// Zeile, über der gerade etwas per Drag & Drop schwebt (für die Hervorhebung).
    @State private var dropTarget: String?

    /// Inhalt eines Drags in der Seitenleiste: Kanal oder Ordner.
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

    /// Eingabedialog zum Anlegen oder Umbenennen eines Ordners.
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
            Section("Übersicht") {
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
                    } label: {
                        Label(folder.name, systemImage: "folder")
                            .badge(count(.folder(folder.id)))
                            .tag(SidebarSelection.folder(folder.id))
                            .draggable("folder:\(folder.id.uuidString)")
                            .dropDestination(for: String.self) { items, _ in
                                dropOnFolder(items, folder: folder.id)
                            } isTargeted: { highlight("folder:\(folder.id)", $0) }
                            .background(dropHighlight("folder:\(folder.id)"))
                            .contextMenu { folderMenu(folder) }
                    }
                }

                ForEach(store.channels(inFolder: nil)) { channel in
                    channelRow(channel)
                }
            } header: {
                Text("Abonnements")
                    // Auf die Überschrift ziehen = ganz nach oben (Kanäle: ohne Ordner).
                    .dropDestination(for: String.self) { items, _ in
                        dropOnHeader(items)
                    } isTargeted: { highlight("header", $0) }
                    .background(dropHighlight("header"))
            }
        }
        .listStyle(.sidebar)
        .contextMenu {
            Button("Neuer Ordner…") { askForNewFolder() }
            Button("Alphabetisch sortieren") { store.sortAlphabetically() }
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
            Button("Abbrechen", role: .cancel) {}
        }
        .onChange(of: store.showingNewFolder) { _, show in
            if show {
                askForNewFolder()
                store.showingNewFolder = false
            }
        }
    }

    // MARK: Zeilen

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
        .dropDestination(for: String.self) { items, _ in
            dropOnChannel(items, target: channel.id)
        } isTargeted: { highlight("channel:\(channel.id)", $0) }
        .background(dropHighlight("channel:\(channel.id)"))
        .contextMenu { channelMenu(channel) }
    }

    @ViewBuilder private func channelMenu(_ channel: Channel) -> some View {
        Menu("In Ordner verschieben") {
            ForEach(store.folders) { folder in
                Button(folder.name) { store.moveChannel(channel.id, toFolder: folder.id) }
                    .disabled(channel.folderID == folder.id)
            }
            if channel.folderID != nil {
                Divider()
                Button("Aus Ordner entfernen") { store.moveChannel(channel.id, toFolder: nil) }
            }
            Divider()
            Button("Neuer Ordner…") { askForNewFolder(moving: channel.id) }
        }
        Button("Nach oben") { store.nudgeChannel(channel.id, by: -1) }
        Button("Nach unten") { store.nudgeChannel(channel.id, by: 1) }
        Button("Alle als gesehen markieren") {
            store.markWatched(store.videos(for: .channel(channel.id), hideShorts: false).map(\.id))
        }
        Divider()
        Button("Abbestellen", role: .destructive) {
            if selection == .channel(channel.id) { selection = .smart(.unwatched) }
            store.removeChannel(channel.id)
        }
    }

    @ViewBuilder private func folderMenu(_ folder: Folder) -> some View {
        Button("Umbenennen…") {
            folderName = folder.name
            prompt = .rename(folder.id)
        }
        Button("Alle als gesehen markieren") {
            store.markWatched(store.videos(for: .folder(folder.id), hideShorts: false).map(\.id))
        }
        Button("Nach oben") { store.nudgeFolder(folder.id, by: -1) }
        Button("Nach unten") { store.nudgeFolder(folder.id, by: 1) }
        Divider()
        Button("Neuer Ordner…") { askForNewFolder() }
        Button("Ordner löschen (Abos bleiben erhalten)", role: .destructive) {
            if selection == .folder(folder.id) { selection = .smart(.unwatched) }
            store.deleteFolder(folder.id)
        }
    }

    @ViewBuilder private var statusLine: some View {
        if store.isRefreshing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Aktualisiere \(store.refreshDone)/\(store.refreshTotal)…")
            }
        } else if let last = store.lastRefresh {
            Text("Aktualisiert \(last, format: .relative(presentation: .named))")
        }
    }

    // MARK: Helfer

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

    /// Kanal auf Kanal: an dessen Stelle (und in dessen Ordner) setzen.
    private func dropOnChannel(_ items: [String], target: String) -> Bool {
        var handled = false
        for case .channel(let id) in items.compactMap(DragItem.init) where store.channel(id) != nil {
            store.moveChannel(id, onto: target)
            handled = true
        }
        return handled
    }

    /// Kanal auf Ordner: hinein (ans Ende). Ordner auf Ordner: an dessen Stelle.
    private func dropOnFolder(_ items: [String], folder: UUID) -> Bool {
        var handled = false
        for item in items.compactMap(DragItem.init) {
            switch item {
            case .channel(let id) where store.channel(id) != nil:
                store.moveChannel(id, toFolder: folder)
                handled = true
            case .folder(let id):
                store.moveFolder(id, onto: folder)
                handled = true
            default:
                break
            }
        }
        return handled
    }

    /// Auf die Überschrift: Ordner ganz nach oben, Kanäle ohne Ordner ganz nach oben.
    private func dropOnHeader(_ items: [String]) -> Bool {
        var handled = false
        for item in items.compactMap(DragItem.init) {
            switch item {
            case .channel(let id) where store.channel(id) != nil:
                store.moveChannel(id, toFolder: nil, atTop: true)
                handled = true
            case .folder(let id):
                store.moveFolderToTop(id)
                handled = true
            default:
                break
            }
        }
        return handled
    }

    private func highlight(_ key: String, _ isTargeted: Bool) {
        if isTargeted {
            dropTarget = key
        } else if dropTarget == key {
            dropTarget = nil
        }
    }

    private func dropHighlight(_ key: String) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.accentColor.opacity(dropTarget == key ? 0.22 : 0))
            .padding(.horizontal, -4)
    }

    private func askForNewFolder(moving channelID: String? = nil) {
        folderName = ""
        prompt = .create(moveChannelID: channelID)
    }

    private var promptTitle: String {
        if case .rename = prompt { return "Ordner umbenennen" }
        return "Neuer Ordner"
    }

    private func promptButtonTitle(_ prompt: FolderPrompt) -> String {
        if case .rename = prompt { return "Umbenennen" }
        return "Anlegen"
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

/// Rundes Kanalbild; Platzhalter, solange keins geladen ist.
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
