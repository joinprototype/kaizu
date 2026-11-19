import OSLog
import WebKit

/// Gives persistent pages a chance to save their final edits, then commits every
/// profile's cookies, before the app process exits.
@MainActor
final class QuitPages: NSObject, WKNavigationDelegate {
    private var pending = Set<ObjectIdentifier>()
    private var deadline: Timer?
    private var cookieStores: [WKHTTPCookieStore] = []
    private var cookieFlushesLeft = 0
    private var unloadedPages = false
    private var completion: (@MainActor () -> Void)?

    private static let flushCookies = NSSelectorFromString("_flushCookiesToDiskWithCompletionHandler:")
    private static let log = Logger(subsystem: Log.subsystem, category: "Quit")

    func start(_ views: [WKWebView], cookieStores: [WKWebsiteDataStore] = [], completion: @escaping @MainActor () -> Void) {
        self.completion = completion
        self.cookieStores = cookieStores.map(\.httpCookieStore)
        unloadedPages = !views.isEmpty
        for view in views {
            view.navigationDelegate = self
            if let navigation = view.loadHTMLString("<title></title>", baseURL: nil) {
                pending.insert(ObjectIdentifier(navigation))
            }
        }
        // An unresponsive renderer must not keep the Mac from quitting.
        deadline = after(2) { self.pagesFinished() }
        if pending.isEmpty { pagesFinished() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let navigation, pending.remove(ObjectIdentifier(navigation)) != nil else { return }
        if pending.isEmpty { pagesFinished() }
    }

    private func pagesFinished() {
        guard deadline != nil else { return }
        deadline?.invalidate()
        deadline = nil
        pending.removeAll()
        // WebKit commits local storage asynchronously after pagehide.
        if unloadedPages {
            _ = after(0.75) { self.commitCookies() }
        } else {
            commitCookies()
        }
    }

    /// WebKit's network process otherwise writes cookies only after this process
    /// has exited. An update relaunches Kaizu at that moment, and the new process
    /// can read the cookie file before the old one has finished writing it.
    private func commitCookies() {
        let stores = cookieStores.filter { $0.responds(to: Self.flushCookies) }
        if stores.count < cookieStores.count {
            Self.log.error("WebKit can't flush cookies before quitting")
        }
        cookieStores = []
        guard !stores.isEmpty else { return finish() }
        cookieFlushesLeft = stores.count
        // A network process that never answers must not keep the Mac from quitting.
        deadline = after(2) {
            Self.log.error("Cookies weren't confirmed on disk before quitting")
            self.finish()
        }
        for store in stores {
            let flushed: @convention(block) () -> Void = { [weak self] in
                if Thread.isMainThread {
                    MainActor.assumeIsolated { self?.cookiesFlushed() }
                } else {
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.cookiesFlushed() } }
                }
            }
            _ = store.perform(Self.flushCookies, with: flushed)
        }
    }

    private func cookiesFlushed() {
        cookieFlushesLeft -= 1
        if cookieFlushesLeft == 0 { finish() }
    }

    private func finish() {
        guard let completion else { return }
        self.completion = nil
        deadline?.invalidate()
        deadline = nil
        completion()
    }

    private func after(_ interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Timer {
        // terminateLater can nest AppKit's modal loop inside a main-actor action.
        // A queued main-actor task cannot resume until that outer action returns.
        let timer = Timer(timeInterval: interval, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .modalPanel)
        return timer
    }
}
