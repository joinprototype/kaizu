import WebKit

/// Gives persistent pages a chance to save their final edits before the app process exits.
@MainActor
final class QuitPages: NSObject, WKNavigationDelegate {
    private var pending = Set<ObjectIdentifier>()
    private var deadline: Task<Void, Never>?
    private var completion: (() -> Void)?

    func start(_ views: [WKWebView], completion: @escaping () -> Void) {
        self.completion = completion
        for view in views {
            view.navigationDelegate = self
            if let navigation = view.loadHTMLString("<title></title>", baseURL: nil) {
                pending.insert(ObjectIdentifier(navigation))
            }
        }
        // An unresponsive renderer must not keep the Mac from quitting.
        deadline = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            finish()
        }
        if pending.isEmpty { finish() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let navigation, pending.remove(ObjectIdentifier(navigation)) != nil else { return }
        if pending.isEmpty { finish() }
    }

    private func finish() {
        guard let completion else { return }
        self.completion = nil
        deadline?.cancel()
        deadline = nil
        Task {
            // WebKit commits local storage asynchronously after pagehide.
            try? await Task.sleep(for: .milliseconds(750))
            completion()
        }
    }
}
