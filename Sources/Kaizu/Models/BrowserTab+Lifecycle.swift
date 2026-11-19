import WebKit

extension BrowserTab {
    /// The live page's back/forward list and scroll position, or what's waiting to be restored.
    var currentState: Data? {
        if leavingForQuit { return savedState }
        return (_webView?.interactionState as? Data) ?? savedState
    }

    /// Capture the real page before WebKit navigates away to deliver pagehide.
    func preparePageForQuit() -> WKWebView? {
        guard !profile.isPrivate, !leavingForQuit, let view = _webView,
              let scheme = view.url?.scheme, scheme == "https" || scheme == "http" else { return nil }
        savedState = currentState
        leavingForQuit = true
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        view.uiDelegate = nil
        return view
    }

    /// Frees the web view's memory; the tab wakes up where it was when shown again.
    func hibernate() {
        guard isLoaded else { return }
        savedState = currentState
        teardown()
    }

    /// Closed for good: torn down, and never given a new web view, even by
    /// a view still fading out with it (which would load the page again).
    func discard() {
        isDiscarded = true
        markNotificationsRead()
        teardown()
    }

    /// Drops the web view but keeps the tab around (used for pinned tabs):
    /// a fresh start at its pinned address.
    func unload() {
        markNotificationsRead()
        teardown()
        savedState = nil
        if let pinnedURL { url = pinnedURL }
    }
}
