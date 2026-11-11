import AVKit
import SwiftUI
import WebKit

/// Embedded YouTube player (youtube-nocookie.com) without recommendations, end screens
/// or info cards, and without a way to navigate from the player to YouTube.
struct YouTubePlayerView: NSViewRepresentable {
    let videoID: String

    /// YouTube requires a Referer for embeds (otherwise error 153). We pass the app as the origin.
    static let baseURL = URL(string: "https://de.videonewswire.app")!

    /// Hides distracting elements in the player. Also injected into the iframe.
    static let hideDistractionsCSS = """
        .ytp-endscreen-content, .ytp-ce-element, .ytp-pause-overlay, .ytp-pause-overlay-container,
        .ytp-related-on-error-overlay, .ytp-suggestion-set, .videowall-endscreen, .html5-endscreen,
        .ytp-show-cards-title, .ytp-cards-button, .ytp-cards-teaser, .iv-branding,
        .ytp-paid-content-overlay, .ytp-youtube-button, .ytp-watermark, .ytp-impression-link,
        .ytp-more-videos-view, .ytp-share-button, .ytp-watch-later-button, .ytp-overflow-button,
        .ytp-title-channel, .ytp-chrome-top-buttons, .ytp-suggested-action, .ytp-featured-product
        { display: none !important; visibility: hidden !important; }
        """

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.isElementFullscreenEnabled = true

        let escapedCSS = Self.hideDistractionsCSS.replacingOccurrences(of: "\n", with: " ")
        let script = """
            (function() {
              var style = document.createElement('style');
              style.textContent = `\(escapedCSS)`;
              (document.head || document.documentElement).appendChild(style);
            })();
            """
        configuration.userContentController.addUserScript(
            WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.underPageBackgroundColor = .black
        load(webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedID != videoID {
            load(webView, coordinator: context.coordinator)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.loadHTMLString("", baseURL: nil)  // stop playback
    }

    private func load(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.loadedID = videoID
        let params = "rel=0&iv_load_policy=3&modestbranding=1&playsinline=1&fs=1&color=white&disablekb=0"
        let html = """
            <!doctype html>
            <html><head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
              html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
              iframe { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
            </style>
            </head><body>
            <iframe src="https://www.youtube-nocookie.com/embed/\(videoID)?\(params)"
                    allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
                    allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe>
            </body></html>
            """
        webView.loadHTMLString(html, baseURL: Self.baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var loadedID: String?

        /// Allow only our own page in the main frame; clicks on YouTube links lead nowhere.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.targetFrame?.isMainFrame == true else {
                // iframe navigation (the player itself) is allowed, pop-ups (targetFrame == nil) are not.
                decisionHandler(navigationAction.targetFrame == nil ? .cancel : .allow)
                return
            }
            let url = navigationAction.request.url
            let allowed = url?.host == YouTubePlayerView.baseURL.host || url?.scheme == "about"
            decisionHandler(allowed ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil  // no new windows
        }
    }
}

/// Playback of a downloaded file: fully offline and ad-free.
struct LocalPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.allowsPictureInPicturePlayback = true
        view.player = AVPlayer(url: url)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if (view.player?.currentItem?.asset as? AVURLAsset)?.url != url {
            view.player?.pause()
            view.player = AVPlayer(url: url)
        }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
    }
}
