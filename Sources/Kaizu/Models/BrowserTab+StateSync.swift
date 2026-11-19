import WebKit

extension BrowserTab {
    func watch<Value>(_ webView: WKWebView, _ keyPath: KeyPath<WKWebView, Value>) -> NSKeyValueObservation {
        webView.observe(keyPath) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                self?.sync(with: webView)
            }
        }
    }

    func sync(with webView: WKWebView) {
        if let newTitle = webView.title, !newTitle.isEmpty, newTitle != title {
            title = newTitle
            app?.scheduleSave()
            app?.extensions.didChange(.title, for: self)
        }
        if let newURL = webView.url, newURL != url {
            if newURL.host() != url?.host() {
                favicon = newURL.host().flatMap { FaviconStore.shared.cachedImage(for: $0) }
            }
            url = newURL
            app?.scheduleSave()
            app?.extensions.didChange(.URL, for: self)
        }
        update(\.isLoading, webView.isLoading)
        update(\.progress, webView.estimatedProgress)
        update(\.canGoBack, webView.canGoBack)
        update(\.canGoForward, webView.canGoForward)
    }

    /// Avoids invalidating SwiftUI views when KVO reports an unchanged value.
    private func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<BrowserTab, T>, _ value: T) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }
}
