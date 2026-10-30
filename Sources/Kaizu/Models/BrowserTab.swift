import AppKit
import BrowserCore
import WebKit

/// A tab owns its WKWebView, created lazily the first time the tab is shown
/// so restored sessions don't load every page at launch.
@MainActor @Observable
final class BrowserTab: NSObject, Identifiable {
    let id: UUID
    let profile: Profile
    var title: String
    var url: URL?
    /// Set while pinned; closing a pinned tab resets it to this URL (Arc-style).
    var pinnedURL: URL?
    var favicon: NSImage?
    var isLoading = false
    var progress = 0.0
    private(set) var isDiscarded = false
    var canGoBack = false
    var canGoForward = false
    /// Last captured picture of the page, for the ⌃Tab switcher.
    var thumbnail: NSImage?
    var isPlayingMedia = false
    /// Muted from the sidebar's speaker; WebKit has no public mute, so
    /// `MediaEvents` mutes the page's media elements, frame by frame.
    var isMuted = false

    /// Last time the tab was in front; today tabs left alone get archived.
    @ObservationIgnored var lastActiveAt: Date?
    @ObservationIgnored weak var store: BrowserStore?
    @ObservationIgnored private var _webView: WKWebView?
    /// This tab's own controller, so content blocking can differ per site.
    @ObservationIgnored private var contentController: WKUserContentController?
    /// Back/forward list, scroll position and form data to restore when the
    /// web view is next created (after a relaunch or waking from hibernation).
    @ObservationIgnored var savedState: Data?
    @ObservationIgnored private var pendingConfiguration: WKWebViewConfiguration?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    /// Bumped when the web view is replaced, so views showing `webView` pick
    /// up the new one.
    private var webViewRevision = 0
    /// Set when the web view was built for an extension's pages.
    @ObservationIgnored private var extensionBaseURL: URL?
    /// The last URL we cleaned of tracking parameters; a redirect straight
    /// back to it with the parameters is let through, so servers that add
    /// them back can't make us loop. Cleared once a page finishes.
    @ObservationIgnored private var lastStrippedURL: URL?
    /// When the page's web content process last died, to stop reload loops.
    @ObservationIgnored private var lastCrash: Date?
    /// Iframes that have played media on this page, so mute reaches them.
    @ObservationIgnored private var mediaFrames: [WKFrameInfo] = []
    /// Its video was floated automatically on switching away.
    @ObservationIgnored private var isInAutoPictureInPicture = false

    init(
        id: UUID = UUID(),
        profile: Profile,
        store: BrowserStore?,
        url: URL?,
        title: String = "",
        pinnedURL: URL? = nil,
        lastActiveAt: Date? = Date(),
        configuration: WKWebViewConfiguration? = nil
    ) {
        self.id = id
        self.profile = profile
        self.store = store
        self.url = url
        self.title = title
        self.pinnedURL = pinnedURL
        self.lastActiveAt = lastActiveAt
        self.pendingConfiguration = configuration
        super.init()
        favicon = url?.host().flatMap { FaviconStore.shared.cachedImage(for: $0) }
    }

    /// A pinned or favorite tab that navigated off its saved page.
    var hasWanderedFromPin: Bool {
        guard let pinnedURL, let url else { return false }
        func normalized(_ url: URL) -> String {
            url.absoluteString.split(separator: "#").first.map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "/")) } ?? ""
        }
        return normalized(url) != normalized(pinnedURL)
    }

    func returnToPin() {
        if let pinnedURL { load(pinnedURL) }
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        return url?.displayHost ?? "New Tab"
    }

    var isLoaded: Bool { _webView != nil }

    var webView: WKWebView {
        _ = webViewRevision
        if let _webView { return _webView }

        // A configuration handed to us by WebKit (window.open / target=_blank)
        // must be used as-is, and WebKit performs the load itself.
        let isPopup = pendingConfiguration != nil
        // Extension pages (options, onboarding) need their extension's own configuration.
        let extensionContext = isPopup || profile.isPrivate ? nil : url.flatMap { store?.extensions.controller.extensionContext(for: $0) }
        extensionBaseURL = extensionContext?.baseURL
        let configuration: WKWebViewConfiguration
        if let extensionConfiguration = extensionContext?.webViewConfiguration {
            configuration = extensionConfiguration
            contentController = nil
        } else {
            let controller = store?.contentBlocker.makeUserContentController()
            configuration = pendingConfiguration ?? Self.makeConfiguration(for: profile)
            // Like other browsers, extensions stay out of private windows.
            configuration.webExtensionController = profile.isPrivate ? nil : store?.extensions.controller
            // Popups get a copy of the opener's configuration; give them their own
            // controller too, so pausing blocking on one site can't leak across tabs.
            if let controller {
                configuration.userContentController = controller
                MediaEvents.install(on: controller, for: self)
                HiddenItems.install(on: controller, for: self)
            }
            contentController = controller
        }
        pendingConfiguration = nil

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.isInspectable = true
        observations = [
            watch(webView, \.title),
            watch(webView, \.url),
            watch(webView, \.isLoading),
            watch(webView, \.estimatedProgress),
            watch(webView, \.canGoBack),
            watch(webView, \.canGoForward),
        ]
        _webView = webView

        if !isPopup {
            let state = savedState
            savedState = nil
            // Hold the first load until content blocking is in place, unless
            // something else has navigated the tab in the meantime.
            let start: @MainActor () -> Void = { [weak webView, url] in
                guard let webView, webView.url == nil, !webView.isLoading else { return }
                if let state {
                    webView.interactionState = state
                } else if let url {
                    webView.load(URLRequest(url: url))
                }
            }
            if let blocker = store?.contentBlocker {
                blocker.whenReady(start)
            } else {
                start()
            }
        }
        return webView
    }

    func activate() {
        guard !isDiscarded else { return }
        _ = webView
    }

    /// For extension pages shown before their extension finished loading.
    func reopenExtensionPage() {
        guard isLoaded, extensionBaseURL == nil, let url, url.scheme == "webkit-extension" else { return }
        reopen(at: url)
    }

    /// Replaces the web view and loads `target` in the new one.
    private func reopen(at target: URL) {
        teardown()
        savedState = nil
        url = target
        activate()
        webViewRevision += 1
    }

    // MARK: - Navigation

    func load(_ url: URL) {
        self.url = url
        if let _webView {
            _webView.load(URLRequest(url: url))
        } else {
            savedState = nil
            activate()
        }
    }

    func goBack() { _webView?.goBack() }
    func goForward() { _webView?.goForward() }
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
            store?.settings.setZoom(zoom, for: url)
        }
        if self === store?.selectedTab {
            store?.showToast("\(Int((zoom * 100).rounded()))%", symbol: "magnifyingglass")
        }
    }

    /// Selects the next (or previous) match, wrapping around. Returns whether there was one.
    func find(_ query: String, backwards: Bool) async -> Bool {
        guard let _webView else { return false }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        return (try? await _webView.find(query, configuration: configuration))?.matchFound ?? false
    }

    // MARK: - Lifecycle

    /// The live page's back/forward list and scroll position, or what's waiting to be restored.
    var currentState: Data? {
        (_webView?.interactionState as? Data) ?? savedState
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
        teardown()
    }

    func printPage() {
        guard let _webView, let window = _webView.window else { return }
        let operation = _webView.printOperation(with: .shared)
        // WKWebView's print view starts with a zero frame and prints blank pages otherwise.
        operation.view?.frame = _webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    /// Saves the whole page as one PDF, asking where (Safari's Export as PDF).
    func exportPDF() {
        guard let _webView, let window = _webView.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = displayTitle.replacingOccurrences(of: "/", with: "-") + ".pdf"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let destination = panel.url else { return }
            Task { @MainActor in
                do {
                    try await _webView.pdf().write(to: destination, options: .atomic)
                } catch {
                    let alert = NSAlert(error: error)
                    alert.messageText = "Couldn't export the page as PDF"
                    alert.beginSheetModal(for: window, completionHandler: nil)
                }
            }
        }
    }

    /// The visible part of the page (or `rect` of it, in the view's
    /// top-left-origin points), as an image.
    func screenshot(of rect: CGRect? = nil) async -> NSImage? {
        guard let _webView, _webView.window != nil else { return nil }
        let configuration = WKSnapshotConfiguration()
        if let rect {
            configuration.rect = rect
        }
        return try? await _webView.takeSnapshot(configuration: configuration)
    }

    /// Snapshots the page for the ⌃Tab switcher. Call while it's on screen.
    func captureThumbnail() {
        guard let _webView, _webView.window != nil else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = 360
        Task {
            if let image = try? await _webView.takeSnapshot(configuration: configuration) {
                thumbnail = image
            }
        }
    }

    /// Media in `frame` started or stopped (from `MediaEvents`).
    func mediaDidChange(in frame: WKFrameInfo) {
        if !frame.isMainFrame {
            mediaFrames = Array((mediaFrames + [frame]).suffix(8))
        }
        if isMuted {
            applyMute(in: frame)
        }
        Task {
            // Let the page's player settle (a pause can briefly still report playing).
            try? await Task.sleep(for: .milliseconds(300))
            await refreshMediaState()
        }
    }

    /// Floats the page's main playing video (audible, the largest) in picture
    /// in picture. Scripts the app runs count as a user gesture, which the
    /// Picture-in-Picture API requires. Call before switching away, while
    /// the page is still on screen: the script is sent right away.
    func enterPictureInPicture() {
        let script = """
        (() => {
          if (document.pictureInPictureElement) return false;
          const video = [...document.querySelectorAll('video')]
            .filter((v) => !v.paused && !v.ended && !v.muted && v.readyState > 2)
            .sort((a, b) => b.clientWidth * b.clientHeight - a.clientWidth * a.clientHeight)[0];
          if (!video) return false;
          if (video.webkitSupportsPresentationMode?.('picture-in-picture')) {
            video.webkitSetPresentationMode('picture-in-picture');
          } else {
            video.requestPictureInPicture();
          }
          return true;
        })()
        """
        _webView?.evaluateJavaScript(script, in: nil, in: .defaultClient) { [weak self] result in
            self?.isInAutoPictureInPicture = (try? result.get()) as? Bool == true
        }
    }

    /// Puts a video floated by `enterPictureInPicture` back in its page.
    func exitPictureInPicture() {
        guard isInAutoPictureInPicture else { return }
        isInAutoPictureInPicture = false
        let script = """
        (() => {
          const video = document.pictureInPictureElement;
          if (!video) return;
          if (video.webkitPresentationMode === 'picture-in-picture') video.webkitSetPresentationMode('inline');
          else document.exitPictureInPicture();
        })()
        """
        _webView?.evaluateJavaScript(script, in: nil, in: .defaultClient)
    }

    func toggleMute() {
        isMuted.toggle()
        applyMute(in: nil)
        mediaFrames.forEach { applyMute(in: $0) }
    }

    private func applyMute(in frame: WKFrameInfo?) {
        _webView?.evaluateJavaScript("window.kaizuSetMuted?.(\(isMuted))", in: frame, in: .defaultClient)
    }

    func refreshMediaState() async {
        guard let _webView else { return }
        let playing = await _webView.requestMediaPlaybackState() == .playing
        if playing != isPlayingMedia { isPlayingMedia = playing }
    }

    func pauseMedia() {
        _webView?.pauseAllMediaPlayback(completionHandler: nil)
        isPlayingMedia = false
    }

    /// Whether the page is playing media or using the camera/microphone,
    /// so it must not be hibernated.
    var isBusy: Bool {
        get async {
            guard let _webView else { return false }
            if _webView.cameraCaptureState != .none || _webView.microphoneCaptureState != .none { return true }
            return await _webView.requestMediaPlaybackState() == .playing
        }
    }

    /// Drops the web view but keeps the tab around (used for pinned tabs):
    /// a fresh start at its pinned address.
    func unload() {
        teardown()
        savedState = nil
        if let pinnedURL { url = pinnedURL }
    }

    func teardown() {
        guard let webView = _webView else { return }
        observations.forEach { $0.invalidate() }
        observations = []
        webView.stopLoading()
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        _webView = nil
        contentController = nil
        mediaFrames = []
        thumbnail = nil
        isPlayingMedia = false
        isLoading = false
        progress = 0
        canGoBack = false
        canGoForward = false
    }

    var record: TabRecord {
        TabRecord(id: id, title: title, url: url, pinnedURL: pinnedURL, lastActiveAt: lastActiveAt)
    }

    // MARK: - State sync

    private func watch<Value>(_ webView: WKWebView, _ keyPath: KeyPath<WKWebView, Value>) -> NSKeyValueObservation {
        webView.observe(keyPath) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                self?.sync(with: webView)
            }
        }
    }

    private func sync(with webView: WKWebView) {
        if let newTitle = webView.title, !newTitle.isEmpty, newTitle != title {
            title = newTitle
            store?.scheduleSave()
            store?.extensions.didChange(.title, for: self)
        }
        if let newURL = webView.url, newURL != url {
            if newURL.host() != url?.host() {
                favicon = newURL.host().flatMap { FaviconStore.shared.cachedImage(for: $0) }
            }
            url = newURL
            store?.scheduleSave()
            store?.extensions.didChange(.URL, for: self)
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

    private func loadFavicon(from webView: WKWebView) async {
        guard let pageURL = webView.url, let host = pageURL.host() else { return }
        let href = (try? await webView.evaluateJavaScript(FaviconStore.discoveryScript)) as? String
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

    static func makeConfiguration(for profile: Profile) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = profile.dataStore
        configuration.applicationNameForUserAgent = UserAgent.safariSuffix
        configuration.preferences.isElementFullscreenEnabled = true
        // HTTPS-first: upgrade every navigation, fall back to HTTP only if it fails.
        configuration.upgradeKnownHostsToHTTPS = true
        configuration.defaultWebpagePreferences.preferredHTTPSNavigationPolicy = .automaticFallbackToHTTP
        if #available(macOS 27.0, *) {
            // "Do not sell or share my data" signal (Sec-GPC header + navigator.globalPrivacyControl).
            configuration.defaultWebpagePreferences.globalPrivacyControlEnabled = true
        }
        return configuration
    }
}

// MARK: - WKNavigationDelegate

extension BrowserTab: WKNavigationDelegate {
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
            let targetExtension = store?.extensions.controller.extensionContext(for: target)?.baseURL
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
            let opensElsewhere = navigationAction.modifierFlags.contains(.command) || navigationAction.buttonNumber == 2
            let wantsPeek = navigationAction.modifierFlags.contains(.shift)
            if navigationAction.navigationType == .linkActivated, !opensElsewhere, !profile.isPrivate, let store, store.peek !== self,
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
            if let contentController {
                store?.contentBlocker.prepare(contentController, for: target)
            }
        }

        // ⌘-click / middle-click opens in a background tab.
        let flags = navigationAction.modifierFlags
        if navigationAction.navigationType == .linkActivated, !profile.isPrivate,
           flags.contains(.command) || navigationAction.buttonNumber == 2 {
            store?.openTab(TrackingParameters.stripped(target) ?? target, after: self, select: flags.contains(.shift))
            return decisionHandler(.cancel)
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
        let zoom = store?.settings.zoom(for: webView.url) ?? 1
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
        let selectors = store?.settings.hiddenItems(on: webView.url) ?? []
        if !selectors.isEmpty {
            HiddenItems.apply(selectors, in: webView)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        lastStrippedURL = nil
        sync(with: webView)
        applyHiddenItems(in: webView)
        if let history = store?.history, let url = webView.url, !profile.isPrivate {
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

// MARK: - WKUIDelegate

extension BrowserTab: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let store else { return nil }
        // Private popups (sign-in windows) open in another private window on
        // the same in-memory profile, keeping `window.opener` working.
        if profile.isPrivate {
            return store.openLittleWindow(profile: profile, configuration: configuration).webView
        }
        let tab = store.openTab(navigationAction.request.url, after: self, configuration: configuration)
        return tab.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        store?.close(self)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        present(alert) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host
        alert.informativeText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        present(alert) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        guard let window = webView.window else { return completionHandler(nil) }
        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    /// Camera and microphone: ask once per site and remember the answer
    /// (except in private windows), instead of WebKit asking on every visit.
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        let devices = switch type {
        case .camera: ["camera"]
        case .microphone: ["microphone"]
        default: ["camera", "microphone"]
        }
        decidePermission(for: origin.host, devices: devices, decisionHandler: decisionHandler)
    }

    @available(macOS 27.0, *)
    func webView(
        _ webView: WKWebView,
        requestGeolocationPermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        decidePermission(for: origin.host, devices: ["location"], decisionHandler: decisionHandler)
    }

    /// Uses a remembered answer, or asks with "Remember for this site".
    /// Answers are shared by every profile, like Safari's website settings;
    /// private windows always ask and never remember.
    private func decidePermission(
        for host: String,
        devices: [String],
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        guard let settings = store?.settings else { return decisionHandler(.prompt) }
        let remembers = !profile.isPrivate
        if remembers {
            let remembered = devices.map { settings.sitePermissions[host]?[$0] }
            if remembered.allSatisfy({ $0 == true }) { return decisionHandler(.grant) }
            if remembered.contains(false) { return decisionHandler(.deny) }
        }

        let alert = NSAlert()
        alert.messageText = "Allow “\(host)” to use your \(devices.joined(separator: " and "))?"
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don’t Allow")
        if remembers {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Remember for this site"
            alert.suppressionButton?.state = .on
        }
        present(alert) { response in
            let allowed = response == .alertFirstButtonReturn
            if remembers, response != .abort, alert.suppressionButton?.state == .on {
                for device in devices {
                    settings.sitePermissions[host, default: [:]][device] = allowed
                }
            }
            decisionHandler(allowed ? .grant : .deny)
        }
    }

    private func confirmOpeningApp(for target: URL) {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: target) else { return }
        let alert = NSAlert()
        alert.messageText = "Open “\(FileManager.default.displayName(atPath: app.path))”?"
        alert.informativeText = "\(url?.displayHost ?? "This page") wants to open this application."
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        present(alert) { response in
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(target)
            }
        }
    }

    /// Shows the alert as a sheet on the tab's window. Pages in the
    /// background get `.abort` instead: an app-modal dialog from a tab you
    /// can't see would freeze the whole browser.
    private func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        guard let window = _webView?.window else { return completion(.abort) }
        alert.beginSheetModal(for: window, completionHandler: completion)
    }
}

// MARK: - Media events

/// Tells a tab when any audio or video in it (iframes included) plays or
/// stops, so the sidebar's speaker and mini player stay current without
/// polling every tab, and mutes media for the tab's mute button (only
/// elements it muted itself are unmuted again). Runs in an isolated world,
/// invisible to pages. The script is one of the content blocker's standard
/// scripts; each tab adds its own message handler.
@MainActor
final class MediaEvents: NSObject, WKScriptMessageHandler {
    private static let name = "kaizuMedia"
    static let script = WKUserScript(
        source: """
        (() => {
          let muted = false;
          const ours = new WeakSet();
          const mute = (media) => {
            if (muted && !media.muted) { media.muted = true; ours.add(media); }
          };
          const post = () => window.webkit?.messageHandlers?.\(name)?.postMessage(0);
          for (const type of ['play', 'pause', 'ended', 'emptied']) {
            document.addEventListener(type, (event) => {
              if (type === 'play') mute(event.target);
              post();
            }, true);
          }
          window.kaizuSetMuted = (value) => {
            muted = value;
            for (const media of document.querySelectorAll('video, audio')) {
              if (value) mute(media);
              else if (ours.has(media)) { media.muted = false; ours.delete(media); }
            }
          };
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false,
        in: .defaultClient
    )

    private weak var tab: BrowserTab?

    static func install(on controller: WKUserContentController, for tab: BrowserTab) {
        let events = MediaEvents()
        events.tab = tab
        controller.add(events, contentWorld: .defaultClient, name: name)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        tab?.mediaDidChange(in: message.frameInfo)
    }
}
