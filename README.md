# VideoNewsWire

A calm YouTube client for macOS, laid out like [NetNewsWire](https://netnewswire.com): **subscriptions on the left, videos in the middle, the video on the right.** No home feed, no recommendations, no comments, no Shorts, no autoplay. Just follow the channels you chose.

![App icon](Resources/AppIcon.iconset/icon_128.png)

## Installation

1. Download the latest `VideoNewsWire-x.y.z.zip` from [**Releases**](https://github.com/zulu101/VideoNewsWire/releases/latest).
2. Unzip it and drag `VideoNewsWire.app` into your **Applications** folder.
3. The app is not notarized by Apple (yet). Before the first launch, run this once in Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/VideoNewsWire.app
   ```
   Alternatively, try to open it, then go to *System Settings → Privacy & Security → Open Anyway*.

Requires **macOS 26 on Apple silicon** (see [Requirements](#requirements)).

## Features

| Area | What it does |
|---|---|
| **Sidebar** | Smart feeds (New · Today · Watch Later · Downloads), **folders** (e.g. Food, Tech) and all subscribed channels with their **channel avatar** |
| **Folders** | ⇧⌘N or right-click → “New Folder…”; move channels in via drag and drop or the context menu; selecting a folder shows the videos of all its channels |
| **Custom order** | Arrange channels and folders by drag and drop: a line shows where the item will land; drop onto a folder name to move a channel into it. Or right-click → “Move Up/Down”. One-off alphabetical sort: right-click → “Sort Alphabetically” |
| **Video list** | Latest videos per channel from YouTube's public RSS feeds, “Mark All as Watched” |
| **Search** | Matches title, channel name, **video description** and existing AI summaries; with several words, all must match |
| **Player** | Embedded via `youtube-nocookie.com`; end screens, info cards, pause overlays, the YouTube logo link etc. are hidden via CSS; navigating away from the player is blocked |
| **AI summary** | On demand, **on-device with Apple Foundation Models** (Apple Intelligence). Based on the subtitles/transcript via yt-dlp, falling back to the video description. Long videos are condensed section by section (map-reduce), because the local model has a context window of only about 4,096 tokens |
| **Download** | Via yt-dlp; the app **installs and updates yt-dlp itself** (every 3 days at launch, or manually). Downloaded videos play locally with AVKit |
| **Import subscriptions** | Manually (URL, @handle, channel ID), from your YouTube account (yt-dlp reads your subscriptions via your browser's cookies) or from a Google Takeout `subscriptions.csv` |

**Languages:** English and German. The app follows your macOS language; AI summaries are written in the same language.

### Designed against distraction

- **No thumbnails** by default (can be turned on in Settings): you pick by title, not by clickbait image.
- **No unread counters** by default: no red numbers urging you to clear a backlog.
- **Shorts hidden** (can be turned on).
- **No autoplay**, no “next video”, no comments, no recommendations.
- New channels don't flood “New”: videos older than 7 days are marked as watched on the first fetch.
- An empty “New” list says: *“No new videos. Time for something else.”*
- No Google sign-in required; the player runs in a non-persistent web data store.

## Requirements

- **macOS 26 (Tahoe)** on **Apple silicon** (for Foundation Models)
- Apple Intelligence turned on (only needed for summaries)
- Xcode 26 / Swift 6.2 to build from source
- Optional: `brew install ffmpeg deno`
  - **ffmpeg**: downloads above 720p (merges video and audio tracks)
  - **deno**: JavaScript runtime recommended by yt-dlp so that all YouTube formats are available

## Building from source

```bash
git clone https://github.com/zulu101/VideoNewsWire.git
cd VideoNewsWire

# Run directly (development)
swift run

# Or build the app bundle → build/VideoNewsWire.app
./Scripts/build-app.sh
```

You can also open `Package.swift` in Xcode and run it from there.

Every push is built by GitHub Actions on a `macos-26` runner; the resulting `VideoNewsWire.zip` is available under *Actions → Build → Artifacts*.

### Publishing a new version

Pushing a version tag creates a GitHub release with the built app automatically (`.github/workflows/release.yml`):

```bash
git tag v0.1.0
git push origin v0.1.0
```

### Translations

English strings in the source code are the keys; translations live in `Resources/<language>.lproj/Localizable.strings` (currently German in `de.lproj`). To add a language, copy `de.lproj`, translate the right-hand side of each line, and add the language code to `CFBundleLocalizations` in `Scripts/build-app.sh`. When running via `swift run` (without an app bundle), the app is always English.

## App icon

The source is `Resources/AppIcon.svg`. After editing the SVG, regenerate the icon:

```bash
node Scripts/make-icon.mjs   # writes Resources/AppIcon.icns and PNGs to Resources/AppIcon.iconset/
```

The script needs Playwright with Chromium (`npm i -g playwright && npx playwright install chromium`).

## Getting started

1. **Settings → Downloads → “Install yt-dlp”** (needed for downloads, transcripts and account import).
2. **⌘N** → add a channel or import the subscriptions from your YouTube account.
   - Importing via **Safari** requires *Full Disk Access* for the app (System Settings → Privacy & Security), because yt-dlp has to read Safari's cookies. Chrome, Firefox and Brave work without it.
3. **⌘R** refreshes all channels.

## Code structure

```
Sources/VideoNewsWire/
├── VideoNewsWireApp.swift      App, menu commands, settings window
├── Model/
│   ├── Models.swift            Channel, Folder, Video, VideoState, settings keys
│   └── AppStore.swift          Persistence (JSON in ~/Library/Application Support/VideoNewsWire)
├── Services/
│   ├── FeedService.swift       Load & parse YouTube RSS feeds
│   ├── ChannelResolver.swift   @handle/URL → channel ID
│   ├── AvatarService.swift     Fetch & cache channel avatars
│   ├── YTDLPManager.swift      Install/update yt-dlp, downloads, subtitles, account subscriptions
│   ├── ProcessRunner.swift     Run external processes asynchronously
│   └── Summarizer.swift        Summaries with Foundation Models (map-reduce)
└── Views/                      SwiftUI: sidebar, list, detail, player, sheets, settings
```

## Known limitations

- YouTube's RSS feeds only contain the **latest 15 videos** per channel and no video duration.
- YouTube feeds are occasionally unavailable for a short time; affected channels show a ⚠️ in the sidebar.
- Hiding player elements relies on YouTube's CSS class names and may need updates when YouTube changes them.
- Fetching many subtitles in a short time can get rate-limited by YouTube (HTTP 429).
- Channel avatars are read from the channel page (`og:image`), cached locally and refreshed every 30 days.
- The local model's summaries are good for an overview but not flawless.

## Disclaimer

- VideoNewsWire is an independent hobby project and is not affiliated with YouTube, Google or the NetNewsWire project. “YouTube” is a trademark of Google LLC.
- The app uses YouTube's public RSS feeds and the official embedded player. Downloads use the separate open-source tool [yt-dlp](https://github.com/yt-dlp/yt-dlp). Only download content you have the rights to, and respect YouTube's Terms of Service.
- All data (subscriptions, state, summaries) stays on your Mac; there is no server and no tracking.

## License

[MIT](LICENSE) © 2026 zulu101
