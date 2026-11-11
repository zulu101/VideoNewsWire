import AppKit
import SwiftUI

struct VideoDetailView: View {
    let video: Video
    @Environment(AppStore.self) private var store
    @Environment(YTDLPManager.self) private var ytdlp

    @State private var showSummary = false
    @State private var isSummarizing = false
    @State private var summaryStatus = ""
    @State private var summaryError: String?
    @State private var summaryTask: Task<Void, Never>?
    @State private var showDescription = false

    var body: some View {
        let state = store.state(video.id)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                player
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.title2.bold())
                        .textSelection(.enabled)
                    HStack(spacing: 6) {
                        ChannelIcon(channelID: video.channelID, size: 18)
                        Text("\(video.channelTitle) · \(video.published.formatted(date: .long, time: .shortened))")
                    }
                    .foregroundStyle(.secondary)
                }

                actionBar(state)

                if showSummary || isSummarizing || summaryError != nil {
                    summarySection(state)
                }

                if !video.descriptionText.isEmpty {
                    DisclosureGroup("Description", isExpanded: $showDescription) {
                        Text(video.descriptionText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .onDisappear { summaryTask?.cancel() }
    }

    @ViewBuilder private var player: some View {
        if let file = store.localFileURL(for: video.id) {
            LocalPlayerView(url: file)
        } else {
            YouTubePlayerView(videoID: video.id)
        }
    }

    // MARK: Actions

    private func actionBar(_ state: VideoState) -> some View {
        HStack(spacing: 8) {
            Button(state.watched ? String(localized: "Mark as New") : String(localized: "Watched"),
                   systemImage: state.watched ? "circle" : "checkmark.circle") {
                store.update(video.id) { $0.watched.toggle() }
            }

            Button(state.saved ? String(localized: "Saved") : String(localized: "Save for Later"),
                   systemImage: state.saved ? "bookmark.fill" : "bookmark") {
                store.update(video.id) { $0.saved.toggle() }
            }

            downloadControl

            Button(showSummary && state.aiSummary != nil ? String(localized: "Hide Summary") : String(localized: "AI Summary"),
                   systemImage: "sparkles") {
                toggleSummary()
            }
            .disabled(isSummarizing)

            Spacer()

            ShareLink(item: video.watchURL) {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Share link")
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder private var downloadControl: some View {
        if let progress = ytdlp.downloadProgress[video.id] {
            HStack(spacing: 6) {
                ProgressView(value: progress).frame(width: 90)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else if let file = store.localFileURL(for: video.id) {
            Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([file])
            }
        } else {
            Button("Download", systemImage: "arrow.down.circle") {
                store.download(video)
            }
            .disabled(!ytdlp.isInstalled)
            .help(ytdlp.isInstalled ? String(localized: "Download with yt-dlp") : String(localized: "Install yt-dlp in Settings"))
        }
    }

    // MARK: Summary

    private func summarySection(_ state: VideoState) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Summary", systemImage: "sparkles").font(.headline)
                    Spacer()
                    if state.aiSummary != nil && !isSummarizing {
                        Button("Regenerate") { generateSummary() }
                            .buttonStyle(.link)
                    }
                }
                if isSummarizing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(summaryStatus).foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { summaryTask?.cancel() }
                            .buttonStyle(.link)
                    }
                } else if let error = summaryError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else if let summary = state.aiSummary {
                    Text(Self.markdown(summary))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Created on this Mac with Apple Intelligence – may contain mistakes.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(6)
        }
    }

    private func toggleSummary() {
        if store.state(video.id).aiSummary != nil {
            showSummary.toggle()
            summaryError = nil
        } else {
            generateSummary()
        }
    }

    private func generateSummary() {
        showSummary = true
        summaryError = nil
        if let reason = Summarizer.unavailableReason {
            summaryError = reason
            return
        }
        isSummarizing = true
        summaryTask = Task {
            defer { isSummarizing = false }
            do {
                summaryStatus = String(localized: "Loading transcript…")
                var source = ""
                if ytdlp.isInstalled {
                    source = (try? await ytdlp.transcript(for: video.id)) ?? ""
                }
                var descriptionOnly = false
                if source.count < 200 {
                    source = video.descriptionText
                    descriptionOnly = true
                }
                guard source.count >= 80 else {
                    throw AppError(ytdlp.isInstalled
                        ? String(localized: "This video has neither subtitles nor a usable description.")
                        : String(localized: "Transcripts require yt-dlp (Settings → Downloads)."))
                }
                let summary = try await Summarizer.summarize(
                    title: video.title, channel: video.channelTitle,
                    text: source, isDescriptionOnly: descriptionOnly
                ) { status in
                    summaryStatus = status
                }
                store.update(video.id) { $0.aiSummary = summary }
            } catch is CancellationError {
                summaryError = String(localized: "Cancelled.")
            } catch {
                summaryError = error.localizedDescription
            }
        }
    }

    private static func markdown(_ string: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: string, options: options)) ?? AttributedString(string)
    }
}
