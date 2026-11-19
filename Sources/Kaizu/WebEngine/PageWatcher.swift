import AppKit
@preconcurrency import UserNotifications
import WebKit

/// Checks watched parts of pages (see `PageWatches`): each page loads in a
/// web view of its own, out of sight, with its profile's cookies (so a
/// signed-in price is the one you'd see) and the usual blocking. One page
/// at a time, at most once an hour each, and never in private windows.
final class PageWatcher: NSObject, WKNavigationDelegate {
    static let interval: TimeInterval = 60 * 60
    /// Pages that draw their content with scripts get this long to show the part.
    static let patience: Duration = .seconds(15)
    static let loadTimeout: Duration = .seconds(30)
    private static let world = WKContentWorld.world(name: "KaizuWatch")

    private weak var app: AppModel?
    private var timer: Task<Void, Never>?
    private var isChecking = false
    private var loaded: CheckedContinuation<Bool, Never>?

    init(app: AppModel) {
        self.app = app
    }

    /// The first round waits a little, so launching stays quick.
    func start(after delay: Duration = .seconds(90)) {
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            while !Task.isCancelled {
                await self?.checkDue()
                try? await Task.sleep(for: .seconds(5 * 60))
            }
        }
    }

    func checkDue() async {
        guard let watches = app?.watches else { return }
        await check(watches.due(every: Self.interval))
    }

    /// Checks these now, one after another.
    func check(_ parts: [WatchedPart]) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        for part in parts {
            guard let app, let profile = app.profiles.first(where: { $0.id == part.profileID }), !profile.isPrivate else { continue }
            let text = await read(part, profile: profile)
            if let changed = app.watches.record(part.id, found: text) {
                await announce(changed)
            }
        }
        app?.updateDockBadge()
    }

    /// The part's text, or nil when the page didn't load or doesn't have it.
    func read(_ part: WatchedPart, profile: Profile) async -> String? {
        let configuration = BrowserTab.makeConfiguration(for: profile)
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        // Out of a window it would be paused before its scripts draw anything.
        configuration.preferences.inactiveSchedulingPolicy = .none
        if let blocker = app?.contentBlocker {
            let controller = blocker.makeUserContentController(privateID: nil)
            await withCheckedContinuation { done in
                blocker.whenReady(for: part.url) {
                    blocker.prepare(controller, for: part.url)
                    done.resume()
                }
            }
            configuration.userContentController = controller
        }
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 900), configuration: configuration)
        webView.navigationDelegate = self
        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
        }
        // A page that never finishes (a stalled request) mustn't hold up the rest.
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: Self.loadTimeout)
            if !Task.isCancelled { self?.finish(false) }
        }
        let finished = await withCheckedContinuation { done in
            loaded = done
            webView.load(URLRequest(url: part.url))
        }
        timeout.cancel()
        guard finished else { return nil }
        return await Self.text(of: part.selector, in: webView)
    }

    /// Looks for the part until it shows up with some text, or patience runs out.
    static func text(of selector: String, in webView: WKWebView, patience: Duration = patience) async -> String? {
        let deadline = ContinuousClock.now + patience
        repeat {
            let found = try? await webView.callAsyncJavaScript(
                """
                let element = null;
                try { element = document.querySelector(selector); } catch { return null; }
                const text = element ? (element.innerText || element.textContent || "") : "";
                return text.trim() ? text : null;
                """,
                arguments: ["selector": selector], in: nil, contentWorld: world) as? String
            if let found { return found }
            try? await Task.sleep(for: .milliseconds(500))
        } while ContinuousClock.now < deadline
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        finish(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        // A redirect cancels the first load and goes on with the next.
        if (error as NSError).code == NSURLErrorCancelled { return }
        finish(false)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        // Never a download, whatever the page turns into.
        decisionHandler(navigationResponse.isForMainFrame && !navigationResponse.canShowMIMEType ? .cancel : .allow)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(false)
    }

    private func finish(_ ok: Bool) {
        loaded?.resume(returning: ok)
        loaded = nil
    }

    /// macOS shows it when it will; otherwise the Dock and the front window do.
    private func announce(_ part: WatchedPart) async {
        #if DEBUG
        Self.onChange?(part)
        #endif
        let delivered = await Self.notify(part)
        guard let app else { return }
        if !delivered {
            NSApp.requestUserAttention(.informationalRequest)
        }
        let text = part.text.count > 60 ? part.text.prefix(60) + "…" : part.text
        app.regularFront.showToast(
            "\(part.title.isEmpty ? part.host : part.title) changed: \(text)",
            symbol: "eye",
            undo: { app.openWatched(part) },
            actionTitle: "Open",
            lasts: .seconds(10)
        )
    }

    #if DEBUG
    static var onChange: ((WatchedPart) -> Void)?
    #endif

    private static func notify(_ part: WatchedPart) async -> Bool {
        guard let center = SiteNotifications.center,
              await center.notificationSettings().authorizationStatus == .authorized else { return false }
        let content = UNMutableNotificationContent()
        content.title = part.title.isEmpty ? part.host : part.title
        content.subtitle = part.host
        content.body = part.previous.map { "\(part.text) (was \($0))" } ?? part.text
        content.threadIdentifier = "watch"
        content.sound = .default
        content.userInfo = SiteNotificationDestination(profileID: part.profileID, url: part.url).userInfo
        let request = UNNotificationRequest(identifier: "watch \(part.id)", content: content, trigger: nil)
        return (try? await center.add(request)) != nil
    }
}

extension AppModel {
    /// Opens a watched page in a new tab of its profile's window.
    func openWatched(_ part: WatchedPart) {
        guard let profile = profiles.first(where: { $0.id == part.profileID }) else { return }
        let window = store(for: profile)
        window.openTab(part.url)
        front = window
        showFront()
        NSApp.activate()
    }
}
