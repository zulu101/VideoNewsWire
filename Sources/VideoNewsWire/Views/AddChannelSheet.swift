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
            Text("Add Channel").font(.title2.bold())

            Text("Channel URL, @handle, channel ID (UC…) or the URL of one of the channel’s videos.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("e.g. @kurzgesagt", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addChannel)
                Button("Add", action: addChannel)
                    .keyboardShortcut(.defaultAction)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)
            }

            Divider().padding(.vertical, 4)

            Text("Import Subscriptions").font(.headline)

            HStack {
                Picker("Browser", selection: $browser) {
                    ForEach(Self.browsers, id: \.id) { Text($0.name).tag($0.id) }
                }
                .frame(width: 200)
                Button("Import from YouTube Account", action: syncFromAccount)
                    .disabled(!ytdlp.isInstalled || isBusy)
            }
            Text("Reads the subscriptions of the YouTube account you’re signed in to in your browser, using yt-dlp. For Safari, the app needs Full Disk Access (System Settings → Privacy & Security).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !ytdlp.isInstalled {
                Text("yt-dlp is not installed yet (Settings → Downloads).")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Google Takeout File (subscriptions.csv)…") { isImportingFile = true }
                    .disabled(isBusy)
            }
            Text("Alternative without browser cookies: takeout.google.com → only “YouTube and YouTube Music” → subscriptions.")
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
                Button("Done") { dismiss() }
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
        run(String(localized: "Looking up channel…")) {
            let channel = try await store.addChannel(text)
            input = ""
            return String(localized: "Added “\(channel.title)”.")
        }
    }

    private func syncFromAccount() {
        run(String(localized: "Reading subscriptions from \(browser)…")) {
            let list = try await ytdlp.subscribedChannels(browser: browser)
            guard !list.isEmpty else { throw AppError(String(localized: "No subscriptions found. Are you signed in to YouTube in your browser?")) }
            message = String(localized: "Found \(list.count) subscriptions, loading feeds…")
            let added = await store.importChannels(list)
            return String(localized: "Imported \(added) new channels (\(list.count) subscriptions in total).")
        }
    }

    private func importCSV(_ url: URL) {
        run(String(localized: "Importing…")) {
            let added = try await store.importTakeoutCSV(from: url)
            return String(localized: "Imported \(added) new channels.")
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
