import SwiftUI
import WebKit

/// An article pulled out of a page for Reader (⇧⌘R), Safari-style.
struct ReaderArticle: Identifiable {
    let id = UUID()
    let tabID: UUID
    let title: String
    let byline: String?
    let siteName: String?
    /// Readability's cleaned-up article HTML (shown with scripts off).
    let content: String
    let baseURL: URL?

    private static let readability = BundledResource.url(named: "readability", extension: "js", in: "Scripts")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

    /// Runs Mozilla's Readability on a copy of the page, in an isolated world
    /// the page can't see. Nil when the page has no article.
    @MainActor
    static func extract(from tab: BrowserTab) async -> ReaderArticle? {
        guard tab.isLoaded, let readability else { return nil }
        let body = readability + """

        const article = new Readability(document.cloneNode(true)).parse();
        if (!article || !article.content || article.textContent.trim().length < 280) return null;
        return { title: article.title || document.title, byline: article.byline, siteName: article.siteName, content: article.content };
        """
        let result = try? await tab.webView.callAsyncJavaScript(body, contentWorld: .defaultClient)
        guard let parsed = result as? [String: Any], let content = parsed["content"] as? String else { return nil }
        return ReaderArticle(
            tabID: tab.id,
            title: parsed["title"] as? String ?? tab.displayTitle,
            byline: parsed["byline"] as? String,
            siteName: parsed["siteName"] as? String ?? tab.url?.host(),
            content: content,
            baseURL: tab.url
        )
    }
}

extension BrowserStore {
    func toggleReader() {
        if reader != nil { return closeReader() }
        guard let tab = selectedTab else { return }
        Task {
            guard let article = await ReaderArticle.extract(from: tab) else {
                return showToast("No article to read on this page", symbol: "doc.plaintext")
            }
            guard tab === selectedTab else { return }
            withAnimation(Motion.glide) { reader = article }
        }
    }

    func closeReader() {
        withAnimation(Motion.snap) { reader = nil }
    }
}
