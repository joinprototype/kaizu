import AppKit
import BrowserCore
import WebKit

extension BrowserTab: WKNavigationDelegate {
    /// WebKit gives buttons as bit flags, not the usual numbers: 2 here is
    /// the right button, as with any link opened from the page's menu.
    private static let middleButton = 4

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.shouldPerformDownload {
            return decisionHandler(.download)
        }
        guard let target = navigationAction.request.url else {
            return decisionHandler(.allow)
        }

        // mailto:, zoommtg:, etc. go to whatever app handles them.
        let webSchemes: Set = ["http", "https", "about", "blob", "data", "file", "javascript", "webkit-extension"]
        if let scheme = target.scheme?.lowercased(), !webSchemes.contains(scheme) {
            decisionHandler(.cancel)
            // A click on the page opens the app; a script asks first (like
            // Safari); a click in an iframe (ads) can't open apps at all.
            // (A click always has a source frame.)
            if navigationAction.navigationType == .linkActivated {
                if navigationAction.sourceFrame.isMainFrame {
                    NSWorkspace.shared.open(target)
                }
            } else if navigationAction.targetFrame?.isMainFrame != false {
                confirmOpeningApp(for: target)
            }
            return
        }

        if navigationAction.targetFrame?.isMainFrame == true {
            // Crossing between web pages and extension pages needs a web view
            // built for the other side (WebKit cancels the load otherwise).
            let targetExtension = app?.extensions.controller.extensionContext(for: target)?.baseURL
            // An extension page restored before its extension has loaded:
            // wait (`reopenExtensionPage()` runs once extensions are in).
            if target.scheme == "webkit-extension", targetExtension == nil {
                return decisionHandler(.cancel)
            }
            if targetExtension != extensionBaseURL {
                decisionHandler(.cancel)
                if !profile.isPrivate {
                    Task { self.reopen(at: target) }
                }
                return
            }
            // Favorites and pinned tabs peek links to other sites instead of leaving.
            // (⌘-click and middle-click still mean "background tab", handled below.)
            // Shift-click peeks any link, from any tab.
            let opensElsewhere = navigationAction.modifierFlags.contains(.command) || navigationAction.buttonNumber == Self.middleButton
            let wantsPeek = navigationAction.modifierFlags.contains(.shift)
            if navigationAction.navigationType == .linkActivated, !opensElsewhere, let store, store.peek !== self,
               wantsPeek || (store.peeksLinks(from: self) && target.siteKey != webView.url?.siteKey) {
                store.peek(TrackingParameters.stripped(target) ?? target, from: self)
                return decisionHandler(.cancel)
            }
            // Strip click-tracking parameters (utm_*, fbclid…) from links and typed URLs.
            if [.linkActivated, .other].contains(navigationAction.navigationType), !opensElsewhere,
               (navigationAction.request.httpMethod ?? "GET") == "GET",
               let cleaned = TrackingParameters.stripped(target),
               !(navigationAction.navigationType == .other && cleaned == lastStrippedURL) {
                lastStrippedURL = cleaned
                decisionHandler(.cancel)
                webView.load(URLRequest(url: cleaned))
                return
            }
        }

        // ⌘-click / middle-click opens in a background tab.
        let flags = navigationAction.modifierFlags
        if navigationAction.navigationType == .linkActivated,
           flags.contains(.command) || navigationAction.buttonNumber == Self.middleButton {
            store?.openTab(TrackingParameters.stripped(target) ?? target, after: self, select: flags.contains(.shift))
            return decisionHandler(.cancel)
        }

        if navigationAction.targetFrame?.isMainFrame == true, let contentController, let blocker = app?.contentBlocker {
            blocker.whenReady(for: target, privateID: profile.privateID) {
                blocker.prepare(contentController, for: target)
                decisionHandler(.allow)
            }
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?
            .lowercased() ?? ""
        if navigationResponse.isForMainFrame,
           !navigationResponse.canShowMIMEType || disposition.hasPrefix("attachment") {
            return decisionHandler(.download)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = DownloadManager.shared
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = DownloadManager.shared
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // Each site keeps its own zoom.
        let zoom = app?.settings.zoom(for: webView.url) ?? 1
        if webView.pageZoom != zoom { webView.pageZoom = zoom }
        // A new page: forget the old one's frames, and stay muted.
        mediaFrames = []
        if isMuted {
            applyMute(in: nil)
        }
        // Picking items belongs to the page it started on.
        if store?.hidingItemsTabID == id {
            store?.endHidingItems()
        }
        applyHiddenItems(in: webView)
    }

    /// The site's hidden items, as early as the page allows and again once
    /// it's in (in case it replaced its head).
    private func applyHiddenItems(in webView: WKWebView) {
        let selectors = app?.settings.hiddenItems(on: webView.url) ?? []
        if !selectors.isEmpty {
            HiddenItems.apply(selectors, in: webView)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        lastStrippedURL = nil
        sync(with: webView)
        applyHiddenItems(in: webView)
        if !profile.isPrivate, let watches = app?.watches, watches.unseenCount > 0 {
            watches.markSeen(webView.url)
        }
        if let history = app?.history, let url = webView.url, !profile.isPrivate {
            let (profileID, title) = (profile.id, webView.title ?? "")
            Task { await history.recordVisit(profile: profileID, url: url, title: title) }
        }
        Task { await loadFavicon(from: webView) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        sync(with: webView)
        let error = error as NSError
        if error.code == NSURLErrorCancelled { return }
        // 102: interrupted by a download / policy change. 204: handled by a media plug-in.
        if error.domain == "WebKitErrorDomain", [102, 204].contains(error.code) { return }
        let failingURL = (error.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? url
        let host = logHost(failingURL)
        Log.navigation.error("Couldn't load \(host, privacy: .private(mask: .hash)): \(error.domain, privacy: .public) \(error.code)")
        webView.loadHTMLString(ErrorPage.html(for: error, url: failingURL), baseURL: failingURL)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let host = logHost(url)
        // Off screen this is usually macOS reclaiming memory: stay unloaded
        // until the tab is shown again.
        guard webView.window != nil else {
            Log.navigation.info("Page process ended off screen (\(host, privacy: .private(mask: .hash))): unloading the tab")
            return hibernate()
        }
        defer { lastCrash = Date() }
        if let lastCrash, Date().timeIntervalSince(lastCrash) < 10 {
            Log.navigation.error("Page keeps crashing (\(host, privacy: .private(mask: .hash))): showing the error page")
            let error = NSError(domain: "Kaizu", code: 1, userInfo: [NSLocalizedDescriptionKey: "This page keeps crashing."])
            webView.loadHTMLString(ErrorPage.html(for: error, url: url), baseURL: url)
        } else {
            Log.navigation.error("Page crashed (\(host, privacy: .private(mask: .hash))): reloading")
            webView.reload()
        }
    }

    /// A page's host for the log (hashed there), never a private window's.
    private func logHost(_ url: URL?) -> String {
        profile.isPrivate ? "private window" : url?.host() ?? "no host"
    }
}

extension BrowserTab {
    private func loadFavicon(from webView: WKWebView) async {
        guard let pageURL = webView.url, let host = pageURL.host() else { return }
        // Not in the page's world, where a script of ours counts as a click:
        // a page hooking the DOM could spend it on asking for permissions.
        let href = (try? await webView.evaluateJavaScript(FaviconStore.discoveryScript, contentWorld: .defaultClient)) as? String
        let candidates = [
            href.flatMap { $0.isEmpty ? nil : URL(string: $0, relativeTo: pageURL) },
            URL(string: "/favicon.ico", relativeTo: pageURL),
        ].compactMap { $0 }
        for candidate in candidates {
            if let image = await FaviconStore.shared.fetch(candidate, host: host, remember: !profile.isPrivate) {
                if url?.host() == host { favicon = image }
                return
            }
        }
    }
}
