import AppKit
import SwiftUI
import WebKit

/// Reader: the article set in a serif on vellum, in a web view with
/// JavaScript off and nothing stored. Links open in the tab.
struct ReaderView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let article: ReaderArticle
    @State private var isLaidOut = false

    var body: some View {
        ZStack {
            // Vellum straight away, the text once it's laid out: Reader
            // never fades in as a blank (or white) page.
            Surface.paper(scheme)
            ReaderWebView(article: article) {
                reveal()
            } openLink: { url in
                store.closeReader()
                store.selectedTab?.load(url)
            }
            .opacity(isLaidOut ? 1 : 0)
        }
        // However the load goes (slow images, a failure), the text shows soon.
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            reveal()
        }
        .overlay(alignment: .topTrailing) {
            IconButton(systemName: "xmark", help: "Close Reader (Esc)") { store.closeReader() }
                .padding(10)
        }
    }

    private func reveal() {
        guard !isLaidOut else { return }
        withAnimation(.easeOut(duration: 0.18)) { isLaidOut = true }
    }
}

private struct ReaderWebView: NSViewRepresentable {
    let article: ReaderArticle
    let didLoad: () -> Void
    let openLink: (URL) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua]) == .darkAqua
                ? NSColor(red: 0.11, green: 0.10, blue: 0.09, alpha: 1)
                : NSColor(red: 0.96, green: 0.94, blue: 0.89, alpha: 1)
        }
        webView.loadHTMLString(Self.html(for: article), baseURL: article.baseURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.didLoad = didLoad
        context.coordinator.openLink = openLink
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(didLoad: didLoad, openLink: openLink)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var didLoad: () -> Void
        var openLink: (URL) -> Void

        init(didLoad: @escaping () -> Void, openLink: @escaping (URL) -> Void) {
            self.didLoad = didLoad
            self.openLink = openLink
        }

        // Laid out a moment after the text arrives; images may still be on
        // their way (that's fine: they take their place as they come).
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            Task {
                try? await Task.sleep(for: .milliseconds(60))
                didLoad()
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didLoad()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            didLoad()
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            didLoad()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
                return decisionHandler(.allow)
            }
            // In-page anchors (footnotes) stay in Reader.
            if url.fragment != nil, url.absoluteString.hasPrefix((webView.url?.absoluteString ?? "") + "#") {
                return decisionHandler(.allow)
            }
            decisionHandler(.cancel)
            openLink(url)
        }
    }

    static func html(for article: ReaderArticle) -> String {
        let site = article.siteName.map { #"<div class="site">\#($0.htmlEscaped)</div>"# } ?? ""
        let byline = article.byline.map { #"<div class="byline">\#($0.htmlEscaped)</div>"# } ?? ""
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src * data:; media-src *; style-src 'unsafe-inline'">
        <title>\(article.title.htmlEscaped)</title>
        <style>
          :root { color-scheme: light dark; --paper: #F4EFE3; --ink: #2B2620; --muted: #7A6F60; --rule: #D9CFBC; --link: #6B2E2A; }
          @media (prefers-color-scheme: dark) { :root { --paper: #1C1A17; --ink: #E8E1D3; --muted: #9A8F7E; --rule: #3A352E; --link: #D9A08B; } }
          html { background: var(--paper); }
          body { font: 20px/1.62 ui-serif, "New York", Georgia, serif; color: var(--ink); max-width: 36em; margin: 0 auto; padding: 72px 32px 120px; -webkit-font-smoothing: antialiased; }
          header { border-bottom: 1px solid var(--rule); margin-bottom: 2em; padding-bottom: 1.2em; }
          .site { font: 600 11px/1 -apple-system, system-ui; letter-spacing: .14em; text-transform: uppercase; color: var(--muted); }
          h1 { font-size: 1.9em; line-height: 1.18; margin: .45em 0 .3em; font-weight: 600; letter-spacing: -.01em; }
          .byline { font-style: italic; color: var(--muted); }
          h2, h3 { line-height: 1.25; margin-top: 1.6em; }
          img, video, figure, iframe { max-width: 100%; height: auto; }
          figure { margin: 1.5em 0; }
          figcaption { font-size: .78em; color: var(--muted); margin-top: .4em; }
          a { color: var(--link); text-decoration-thickness: 1px; text-underline-offset: 3px; }
          blockquote { border-left: 2px solid var(--rule); margin: 1.4em 0; padding-left: 1em; color: var(--muted); font-style: italic; }
          pre, code { font: 15px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
          pre { overflow-x: auto; background: rgba(127, 110, 80, .08); padding: 1em; border-radius: 6px; }
          hr { border: 0; border-top: 1px solid var(--rule); margin: 2em 0; }
          table { border-collapse: collapse; font-size: .85em; }
          td, th { border-bottom: 1px solid var(--rule); padding: .4em .6em; }
        </style>
        </head>
        <body><header>\(site)<h1>\(article.title.htmlEscaped)</h1>\(byline)</header><article>\(article.content)</article></body>
        </html>
        """
    }
}
