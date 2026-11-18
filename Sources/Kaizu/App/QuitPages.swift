import WebKit

/// Gives persistent pages a chance to save their final edits before the app process exits.
@MainActor
final class QuitPages: NSObject, WKNavigationDelegate {
    private var pending = Set<ObjectIdentifier>()
    private var deadline: Timer?
    private var completion: (@MainActor () -> Void)?

    func start(_ views: [WKWebView], completion: @escaping @MainActor () -> Void) {
        self.completion = completion
        for view in views {
            view.navigationDelegate = self
            if let navigation = view.loadHTMLString("<title></title>", baseURL: nil) {
                pending.insert(ObjectIdentifier(navigation))
            }
        }
        // An unresponsive renderer must not keep the Mac from quitting.
        deadline = after(2) { self.finish() }
        if pending.isEmpty { finish() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let navigation, pending.remove(ObjectIdentifier(navigation)) != nil else { return }
        if pending.isEmpty { finish() }
    }

    private func finish() {
        guard let completion else { return }
        self.completion = nil
        deadline?.invalidate()
        deadline = nil
        // WebKit commits local storage asynchronously after pagehide.
        _ = after(0.75, completion)
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
