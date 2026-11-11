import SwiftUI

/// Three-pane layout like NetNewsWire: sidebar · video list · video.
struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(YTDLPManager.self) private var ytdlp
    @AppStorage(Prefs.markWatchedOnOpen) private var markWatchedOnOpen = true

    @State private var sidebarSelection: SidebarSelection? = .smart(.unwatched)
    @State private var selectedVideoID: String?

    var body: some View {
        @Bindable var store = store

        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } content: {
            VideoListView(selection: sidebarSelection ?? .smart(.unwatched), selectedVideoID: $selectedVideoID)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
        } detail: {
            if let id = selectedVideoID, let video = store.videos[id] {
                VideoDetailView(video: video)
                    .id(id)
            } else {
                ContentUnavailableView("No Video Selected", systemImage: "play.rectangle",
                                       description: Text("Choose a video on the left."))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await store.refreshAll() }
                }
                .disabled(store.isRefreshing)
                .help("Refresh all channels (⌘R)")

                Button("Add Channel", systemImage: "plus") {
                    store.showingAddChannel = true
                }
                .help("Add a channel (⌘N)")
            }
        }
        .onChange(of: sidebarSelection) { _, _ in
            selectedVideoID = nil
        }
        .onChange(of: selectedVideoID) { _, id in
            if let id, markWatchedOnOpen, !store.state(id).watched {
                store.update(id) { $0.watched = true }
            }
        }
        .sheet(isPresented: $store.showingAddChannel) {
            AddChannelSheet()
        }
        .alert("Error", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .task {
            // Refresh at launch, but not more often than every 15 minutes.
            if Date().timeIntervalSince(store.lastRefresh ?? .distantPast) > 15 * 60 {
                await store.refreshAll()
            }
            await ytdlp.updateIfNeeded()
        }
    }
}
