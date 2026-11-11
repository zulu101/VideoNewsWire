import AppKit
import SwiftUI

@main
struct VideoNewsWireApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore.shared
    @State private var ytdlp = YTDLPManager.shared

    init() {
        Prefs.registerDefaults()
    }

    var body: some Scene {
        Window("VideoNewsWire", id: "main") {
            ContentView()
                .environment(store)
                .environment(ytdlp)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Channel…") { store.showingAddChannel = true }
                    .keyboardShortcut("n")
                Button("New Folder…") { store.showingNewFolder = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandMenu("Videos") {
                Button("Refresh All Channels") {
                    Task { await store.refreshAll() }
                }
                .keyboardShortcut("r")
                .disabled(store.isRefreshing)
            }
        }

        Settings {
            SettingsView()
                .environment(store)
                .environment(ytdlp)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when the app is started directly via `swift run` (without an .app bundle).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
