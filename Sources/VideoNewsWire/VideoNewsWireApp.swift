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
                Button("Kanal hinzufügen…") { store.showingAddChannel = true }
                    .keyboardShortcut("n")
            }
            CommandMenu("Videos") {
                Button("Alle Kanäle aktualisieren") {
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
        // Nötig, wenn die App direkt per `swift run` (ohne .app-Bundle) gestartet wird.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
