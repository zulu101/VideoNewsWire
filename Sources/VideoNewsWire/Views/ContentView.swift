import SwiftUI

/// Drei-Spalten-Layout wie NetNewsWire: Seitenleiste · Videoliste · Video.
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
                ContentUnavailableView("Kein Video ausgewählt", systemImage: "play.rectangle",
                                       description: Text("Wähle links ein Video aus."))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Aktualisieren", systemImage: "arrow.clockwise") {
                    Task { await store.refreshAll() }
                }
                .disabled(store.isRefreshing)
                .help("Alle Kanäle aktualisieren (⌘R)")

                Button("Kanal hinzufügen", systemImage: "plus") {
                    store.showingAddChannel = true
                }
                .help("Kanal hinzufügen (⌘N)")
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
        .alert("Fehler", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .task {
            // Beim Start aktualisieren, aber nicht öfter als alle 15 Minuten.
            if Date().timeIntervalSince(store.lastRefresh ?? .distantPast) > 15 * 60 {
                await store.refreshAll()
            }
            await ytdlp.updateIfNeeded()
        }
    }
}
