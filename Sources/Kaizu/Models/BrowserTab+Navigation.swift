import WebKit

extension BrowserTab {
    func load(_ url: URL) {
        self.url = url
        crossedForward = []
        if let _webView {
            _webView.load(URLRequest(url: url))
        } else {
            savedState = nil
            activate()
        }
    }

    func goBack() {
        guard let _webView else { return }
        if _webView.canGoBack {
            _webView.goBack()
        } else {
            step(back: true)
        }
    }

    func goForward() {
        guard let _webView else { return }
        if _webView.canGoForward {
            _webView.goForward()
        } else {
            step(back: false)
        }
    }
    func stopLoading() { _webView?.stopLoading() }

    func reload(fromOrigin: Bool = false) {
        guard !isDiscarded else { return }
        guard let _webView else { return activate() }
        if fromOrigin {
            _webView.reloadFromOrigin()
        } else {
            _webView.reload()
        }
    }

    func zoom(by delta: Double) {
        guard let _webView else { return }
        setZoom(min(max(_webView.pageZoom + delta, 0.5), 3))
    }

    func resetZoom() {
        setZoom(1)
    }

    /// Applies and remembers the zoom for this site (not from private windows).
    private func setZoom(_ zoom: Double) {
        _webView?.pageZoom = zoom
        if !profile.isPrivate {
            app?.settings.setZoom(zoom, for: url)
        }
        if self === store?.selectedTab {
            store?.showToast("\(Int((zoom * 100).rounded()))%", symbol: "magnifyingglass")
        }
    }
}
