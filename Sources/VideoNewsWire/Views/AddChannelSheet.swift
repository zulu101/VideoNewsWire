import SwiftUI
import UniformTypeIdentifiers

struct AddChannelSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(YTDLPManager.self) private var ytdlp
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.cookieBrowser) private var browser = "safari"

    @State private var input = ""
    @State private var isBusy = false
    @State private var message: String?
    @State private var isImportingFile = false

    static let browsers: [(id: String, name: String)] = [
        ("safari", "Safari"), ("chrome", "Chrome"), ("firefox", "Firefox"), ("brave", "Brave"),
        ("edge", "Edge"), ("vivaldi", "Vivaldi"), ("opera", "Opera"), ("chromium", "Chromium"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Kanal hinzufügen").font(.title2.bold())

            Text("Kanal-URL, @Handle, Kanal-ID (UC…) oder die URL eines Videos des Kanals.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("z. B. @kurzgesagt", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addChannel)
                Button("Hinzufügen", action: addChannel)
                    .keyboardShortcut(.defaultAction)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)
            }

            Divider().padding(.vertical, 4)

            Text("Abos importieren").font(.headline)

            HStack {
                Picker("Browser", selection: $browser) {
                    ForEach(Self.browsers, id: \.id) { Text($0.name).tag($0.id) }
                }
                .frame(width: 200)
                Button("Aus YouTube-Konto übernehmen", action: syncFromAccount)
                    .disabled(!ytdlp.isInstalled || isBusy)
            }
            Text("Liest die Abos deines im Browser angemeldeten YouTube-Kontos mit yt-dlp aus. "
                 + "Für Safari benötigt die App Festplattenvollzugriff (Systemeinstellungen → Datenschutz & Sicherheit).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !ytdlp.isInstalled {
                Text("yt-dlp ist noch nicht installiert (Einstellungen → Downloads).")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Google-Takeout-Datei (subscriptions.csv)…") { isImportingFile = true }
                    .disabled(isBusy)
            }
            Text("Alternative ohne Browser-Cookies: takeout.google.com → nur „YouTube und YouTube Music“ → Abos.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isBusy || message != nil {
                HStack(spacing: 8) {
                    if isBusy { ProgressView().controlSize(.small) }
                    if let message { Text(message).fixedSize(horizontal: false, vertical: true) }
                }
            }

            HStack {
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 540)
        .fileImporter(isPresented: $isImportingFile,
                      allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            switch result {
            case .success(let url): importCSV(url)
            case .failure(let error): message = error.localizedDescription
            }
        }
    }

    private func addChannel() {
        let text = input
        run("Suche Kanal…") {
            let channel = try await store.addChannel(text)
            input = ""
            return "„\(channel.title)“ hinzugefügt."
        }
    }

    private func syncFromAccount() {
        run("Lese Abos aus \(browser)…") {
            let list = try await ytdlp.subscribedChannels(browser: browser)
            guard !list.isEmpty else { throw AppError("Keine Abos gefunden. Bist du im Browser bei YouTube angemeldet?") }
            message = "\(list.count) Abos gefunden, lade Feeds…"
            let added = await store.importChannels(list)
            return "\(added) neue Kanäle übernommen (\(list.count) Abos insgesamt)."
        }
    }

    private func importCSV(_ url: URL) {
        run("Importiere…") {
            let added = try await store.importTakeoutCSV(from: url)
            return "\(added) neue Kanäle importiert."
        }
    }

    private func run(_ status: String, _ operation: @escaping () async throws -> String) {
        isBusy = true
        message = status
        Task {
            do {
                message = try await operation()
            } catch {
                message = error.localizedDescription
            }
            isBusy = false
        }
    }
}
