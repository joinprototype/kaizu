import WebKit

/// A web view this tab left by crossing between web pages and extension
/// pages: its back/forward list and where it was.
struct CrossedPage {
    let state: Data
    let url: URL
}

extension BrowserTab {
    /// Enough to get back through a settings page or two, without holding
    /// on to every page's state.
    static let crossedLimit = 10

    /// Web pages and extension pages need web views built for their side,
    /// so going from one to the other starts a new one: the old one is kept
    /// for Back.
    func cross(to target: URL) {
        if let page = crossedPage {
            crossedBack = Array((crossedBack + [page]).suffix(Self.crossedLimit))
        }
        crossedForward = []
        reopen(at: target)
        syncCrossing()
    }

    /// Back or Forward past the current web view's own list: brings back the
    /// one before (or after) it, and keeps the current one for the way back.
    /// Pages of an extension removed since are skipped.
    func step(back: Bool) {
        var source = back ? crossedBack : crossedForward
        guard let index = source.lastIndex(where: canReopen) else { return }
        let page = source[index]
        source.removeSubrange(index...)
        var destination = back ? crossedForward : crossedBack
        if let current = crossedPage {
            destination = Array((destination + [current]).suffix(Self.crossedLimit))
        }
        (crossedBack, crossedForward) = back ? (source, destination) : (destination, source)
        teardown()
        savedState = page.state
        url = page.url
        activate()
        webViewRevision += 1
        syncCrossing()
    }

    private var crossedPage: CrossedPage? {
        guard let view = _webView, let url = view.url, let state = view.interactionState as? Data else { return nil }
        return CrossedPage(state: state, url: url)
    }

    private func canReopen(_ page: CrossedPage) -> Bool {
        page.url.scheme != "webkit-extension" || app?.extensions.controller.extensionContext(for: page.url) != nil
    }

    /// The new web view's KVO hasn't reported yet: count what's kept aside.
    private func syncCrossing() {
        canGoBack = (_webView?.canGoBack ?? false) || !crossedBack.isEmpty
        canGoForward = (_webView?.canGoForward ?? false) || !crossedForward.isEmpty
    }
}
