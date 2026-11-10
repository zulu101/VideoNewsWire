import SwiftUI

struct SidebarView: View {
    @Environment(AppStore.self) private var store
    @Binding var selection: SidebarSelection?
    @AppStorage(Prefs.showUnreadCounts) private var showCounts = false
    @AppStorage(Prefs.hideShorts) private var hideShorts = true

    var body: some View {
        List(selection: $selection) {
            Section("Übersicht") {
                ForEach(SmartFeed.allCases, id: \.self) { feed in
                    Label(feed.title, systemImage: feed.systemImage)
                        .badge(count(.smart(feed)))
                        .tag(SidebarSelection.smart(feed))
                }
            }

            Section("Abonnements") {
                ForEach(store.channels) { channel in
                    HStack {
                        Label(channel.title, systemImage: "person.crop.square")
                            .lineLimit(1)
                        if let error = channel.lastError {
                            Spacer()
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .help(error)
                        }
                    }
                    .badge(count(.channel(channel.id)))
                    .tag(SidebarSelection.channel(channel.id))
                    .contextMenu {
                        Button("Alle als gesehen markieren") {
                            store.markWatched(store.videos(for: .channel(channel.id), hideShorts: false).map(\.id))
                        }
                        Divider()
                        Button("Abbestellen", role: .destructive) {
                            if selection == .channel(channel.id) { selection = .smart(.unwatched) }
                            store.removeChannel(channel.id)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            statusLine
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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

    private func count(_ selection: SidebarSelection) -> Int {
        showCounts ? store.unwatchedCount(selection, hideShorts: hideShorts) : 0
    }
}
