import AVKit
import SwiftUI
import WebKit

/// Eingebetteter YouTube-Player (youtube-nocookie.com) ohne Empfehlungen, Endscreens,
/// Info-Karten und ohne Möglichkeit, aus dem Player heraus zu YouTube zu navigieren.
struct YouTubePlayerView: NSViewRepresentable {
    let videoID: String

    /// YouTube verlangt für Embeds einen Referer (sonst Fehler 153). Wir geben die App als Herkunft an.
    static let baseURL = URL(string: "https://de.videonewswire.app")!

    /// Blendet ablenkende Elemente im Player aus. Wird auch in den iframe injiziert.
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
        webView.loadHTMLString("", baseURL: nil)  // Wiedergabe stoppen
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

        /// Nur die eigene Seite im Hauptframe zulassen – Klicks auf YouTube-Links führen nirgendwohin.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.targetFrame?.isMainFrame == true else {
                // iframe-Navigation (der Player selbst) ist erlaubt, Pop-ups (targetFrame == nil) nicht.
                decisionHandler(navigationAction.targetFrame == nil ? .cancel : .allow)
                return
            }
            let url = navigationAction.request.url
            let allowed = url?.host == YouTubePlayerView.baseURL.host || url?.scheme == "about"
            decisionHandler(allowed ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil  // keine neuen Fenster
        }
    }
}

/// Wiedergabe einer heruntergeladenen Datei – komplett offline und werbefrei.
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
