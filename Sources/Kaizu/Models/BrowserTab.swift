import AppKit
import BrowserCore
import WebKit

/// A tab owns its WKWebView, created lazily the first time the tab is shown
/// so restored sessions don't load every page at launch.
@Observable
final class BrowserTab: NSObject, Identifiable {
    let id: UUID
    let profile: Profile
    var title: String
    var url: URL?
    /// Set while pinned; closing a pinned tab resets it to this URL (Arc-style).
    var pinnedURL: URL?
    /// The name given to it, if any; the page's title otherwise.
    var customTitle: String?
    let arcItemID: UUID?
    var favicon: NSImage?
    var isLoading = false
    var progress = 0.0
    var isDiscarded = false
    var canGoBack = false
    var canGoForward = false
    /// Last captured picture of the page, for the ⌃Tab switcher.
    var thumbnail: NSImage?
    /// Making sound, or would be if you hadn't muted it: see `isPlayingSound`.
    var isPlayingMedia = false
    /// Muted from the sidebar's speaker; WebKit has no public mute, so
    /// `MediaEvents` mutes the page's media elements, frame by frame.
    var isMuted = false

    /// Last time the tab was in front; today tabs left alone get archived.
    @ObservationIgnored var lastActiveAt: Date?
    @ObservationIgnored weak var app: AppModel?
    /// Fills logins from the Passwords app; nil on extension pages.
    @ObservationIgnored var passwordFill: PasswordFill?
    /// The window showing this tab, or the one it belongs to while it's off
    /// screen. Never simply the one in front: a private page's popup could
    /// land outside its window, with its cookies and into the session.
    var store: BrowserStore? { app.map { $0.store(showing: self) ?? $0.store(for: profile) } }
    @ObservationIgnored private(set) var _webView: WKWebView?
    /// This tab's own controller, so content blocking can differ per site.
    @ObservationIgnored private(set) var contentController: WKUserContentController?
    /// Back/forward list, scroll position and form data to restore when the
    /// web view is next created (after a relaunch or waking from hibernation).
    @ObservationIgnored var savedState: Data?
    @ObservationIgnored var leavingForQuit = false
    @ObservationIgnored private var pendingConfiguration: WKWebViewConfiguration?
    @ObservationIgnored var observations: [NSKeyValueObservation] = []
    /// Bumped when the web view is replaced, so views showing `webView` pick
    /// up the new one.
    var webViewRevision = 0
    /// Set when the web view was built for an extension's pages.
    @ObservationIgnored private(set) var extensionBaseURL: URL?
    /// The last URL we cleaned of tracking parameters; a redirect straight
    /// back to it with the parameters is let through, so servers that add
    /// them back can't make us loop. Cleared once a page finishes.
    @ObservationIgnored var lastStrippedURL: URL?
    /// When the page's web content process last died, to stop reload loops.
    @ObservationIgnored var lastCrash: Date?
    /// Iframes that have played media on this page, so mute reaches them.
    @ObservationIgnored var mediaFrames: [WKFrameInfo] = []
    /// Its video was floated automatically on switching away.
    @ObservationIgnored var isInAutoPictureInPicture = false
    /// Web views left behind by crossing between web pages and extension
    /// pages, whose back/forward lists WebKit can't join: Back and Forward
    /// step into them once the current one runs out. Not saved.
    @ObservationIgnored var crossedBack: [CrossedPage] = []
    @ObservationIgnored var crossedForward: [CrossedPage] = []

    init(
        id: UUID = UUID(),
        profile: Profile,
        app: AppModel?,
        url: URL?,
        title: String = "",
        pinnedURL: URL? = nil,
        lastActiveAt: Date? = Date(),
        arcItemID: UUID? = nil,
        configuration: WKWebViewConfiguration? = nil
    ) {
        self.id = id
        self.profile = profile
        self.arcItemID = arcItemID
        self.app = app
        self.url = url
        self.title = title
        self.pinnedURL = pinnedURL
        self.lastActiveAt = lastActiveAt
        self.pendingConfiguration = configuration
        super.init()
        favicon = url?.host().flatMap { FaviconStore.shared.cachedImage(for: $0) }
    }

    convenience init(reopening record: TabRecord, id: UUID = UUID(), profile: Profile, app: AppModel?, navigationState: Data?) {
        self.init(id: id, profile: profile, app: app, url: record.url, title: record.title, arcItemID: record.arcItemID)
        customTitle = record.customTitle
        savedState = navigationState
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
        if let customTitle { return customTitle }
        if !title.isEmpty { return title }
        return url?.displayHost ?? "New Tab"
    }

    /// Where the page's menu just sent a link, for WebKit to ask about.
    @ObservationIgnored var linkDestination: LinkDestination?
    /// Made from WebKit's configuration for `window.open`. It's left alone:
    /// rebuilding it would cut it off from the page that opened it.
    private(set) var isPopupPage = false

    /// Notifications from this page you haven't looked at. Not saved.
    var unreadNotifications = 0 {
        didSet { app?.updateDockBadge() }
    }

    var isLoaded: Bool { _webView != nil }

    var webView: WKWebView {
        _ = webViewRevision
        if let _webView { return _webView }

        // A configuration handed to us by WebKit (window.open / target=_blank)
        // must be used as-is, and WebKit performs the load itself.
        isPopupPage = pendingConfiguration != nil
        // Extension pages (options, onboarding) need their extension's own configuration.
        let extensionContext = isPopupPage || profile.isPrivate ? nil : url.flatMap { app?.extensions.controller.extensionContext(for: $0) }
        extensionBaseURL = extensionContext?.baseURL
        let configuration: WKWebViewConfiguration
        if let extensionConfiguration = extensionContext?.webViewConfiguration {
            configuration = extensionConfiguration
            contentController = nil
        } else {
            let controller = app?.contentBlocker.makeUserContentController(privateID: profile.privateID)
            configuration = pendingConfiguration ?? Self.makeConfiguration(for: profile)
            // Like other browsers, extensions stay out of private windows.
            configuration.webExtensionController = profile.isPrivate ? nil : app?.extensions.controller
            // Popups get a copy of the opener's configuration; give them their own
            // controller too, so pausing blocking on one site can't leak across tabs.
            if let controller {
                configuration.userContentController = controller
                MediaEvents.install(on: controller, for: self)
                HiddenItems.install(on: controller, for: self)
                SiteNotifications.install(on: controller, for: self)
                passwordFill = PasswordFill.install(on: controller, for: self)
            }
            contentController = controller
        }
        pendingConfiguration = nil
        // A web view out of a window is paused otherwise, which is every tab
        // but the one on screen: hidden, a chat site's socket stalled for
        // 46 s, against 0.8 s throttled (Nov 1).
        if notifyingHost != nil {
            configuration.preferences.inactiveSchedulingPolicy = .throttle
        }

        let webView = PageWebView(frame: .zero, configuration: configuration)
        webView.tab = self
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

        if !isPopupPage {
            if let state = savedState {
                savedState = nil
                webView.interactionState = state
            } else if let url {
                webView.load(URLRequest(url: url))
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
    func reopen(at target: URL) {
        teardown()
        savedState = nil
        url = target
        activate()
        webViewRevision += 1
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
        isPopupPage = false
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
        TabRecord(id: id, title: title, url: url, pinnedURL: pinnedURL, lastActiveAt: lastActiveAt, customTitle: customTitle, arcItemID: arcItemID)
    }
}
