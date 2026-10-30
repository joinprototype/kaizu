import BrowserCore
import CryptoKit
import OSLog
import WebKit

/// Built-in ad, tracker and cookie-banner blocking, YouTube ad removal, and
/// automatic rejection of cookie consent pop-ups (DuckDuckGo's autoconsent).
///
/// Filter lists are converted to WebKit content rules, compiled once and
/// cached by WebKit (keyed by list contents and converter version). Each tab
/// gets its own user content controller so blocking can be paused per site
/// without recompiling anything.
@MainActor @Observable
final class ContentBlocker {
    enum State: Equatable {
        case idle
        case preparing
        case ready
    }

    /// What a tab's content controller currently has installed.
    private struct Setup: Equatable {
        var blocking: Bool
        var cookieRejection: Bool
        var listGeneration: Int
    }

    /// Compiled separately: WebKit caps a list at 150k rules, and an
    /// `ignore-previous-rules` exception only affects its own list.
    static let listNames = ["easylist", "easyprivacy", "cookies", "kaizu"]
    /// How long a tab's first load waits for blocking before going ahead without it.
    static let readyTimeout: Duration = .seconds(3)
    private static let enabledKey = "contentBlockingEnabled"
    private static let cookieRejectionKey = "cookiePopupRejectionEnabled"
    private static let pausedSitesKey = "blockingPausedSites"

    private(set) var state: State = .idle
    private(set) var isEnabled: Bool
    private(set) var isCookieRejectionEnabled: Bool
    /// Sites (and their subdomains) where the user turned blocking off.
    private(set) var pausedSites: Set<String>

    @ObservationIgnored private var ruleLists: [(name: String, list: WKContentRuleList)] = []
    @ObservationIgnored private var listGeneration = 0
    @ObservationIgnored private let controllers = NSHashTable<WKUserContentController>.weakObjects()
    @ObservationIgnored private var installed: [ObjectIdentifier: Setup] = [:]
    @ObservationIgnored private var currentSite: [ObjectIdentifier: String] = [:]
    @ObservationIgnored private var readyHandlers: [@MainActor () -> Void] = []
    /// Scripts every page gets whatever the blocking settings; reinstalls
    /// (which clear a controller's scripts) put them back.
    @ObservationIgnored var standardScripts: [WKUserScript] = []
    /// Set once the ready timeout passes: later tabs stop waiting too.
    @ObservationIgnored private var hasTimedOut = false
    @ObservationIgnored private let log = Logger(subsystem: Log.subsystem, category: "ContentBlocker")

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        isCookieRejectionEnabled = defaults.object(forKey: Self.cookieRejectionKey) as? Bool ?? true
        pausedSites = Set(defaults.stringArray(forKey: Self.pausedSitesKey) ?? [])
    }

    func start() {
        guard state == .idle else { return }
        state = .preparing
        Task {
            await loadLists()
            if await FilterListUpdater.updateIfDue() {
                await loadLists()
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: Self.readyTimeout)
            self?.hasTimedOut = true
            self?.runReadyHandlers()
        }
    }

    /// Runs `handler` once blocking is in place (or the timeout passes), so
    /// a tab's first load isn't unprotected.
    func whenReady(_ handler: @escaping @MainActor () -> Void) {
        if state == .ready || hasTimedOut || !isEnabled {
            handler()
        } else {
            readyHandlers.append(handler)
        }
    }

    // MARK: - Settings

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        installEverywhere()
    }

    func setCookieRejectionEnabled(_ enabled: Bool) {
        isCookieRejectionEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.cookieRejectionKey)
        installEverywhere()
    }

    func isPaused(on url: URL?) -> Bool {
        pausedEntry(for: url.flatMap(Self.site(for:))) != nil
    }

    /// Pauses or resumes blocking on the URL's site. Returns the new paused state.
    @discardableResult
    func togglePause(on url: URL) -> Bool {
        guard let site = Self.site(for: url) else { return false }
        if let entry = pausedEntry(for: site) {
            resume(entry)
        } else {
            updatePausedSites { _ = $0.insert(site) }
        }
        return isPaused(on: url)
    }

    func resume(_ site: String) {
        updatePausedSites { _ = $0.remove(site) }
    }

    private func updatePausedSites(_ change: (inout Set<String>) -> Void) {
        change(&pausedSites)
        UserDefaults.standard.set(pausedSites.sorted(), forKey: Self.pausedSitesKey)
        installEverywhere()
    }

    static func site(for url: URL) -> String? {
        guard let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func pausedEntry(for site: String?) -> String? {
        guard let site else { return nil }
        return pausedSites.first { site == $0 || site.hasSuffix("." + $0) }
    }

    // MARK: - Tabs

    /// A fresh controller for a new web view, with blocking installed.
    func makeUserContentController() -> WKUserContentController {
        let controller = WKUserContentController()
        let key = ObjectIdentifier(controller)
        // Identifiers of deallocated controllers can be reused.
        installed[key] = nil
        currentSite[key] = nil
        controllers.add(controller)
        install(on: controller)
        return controller
    }

    /// Call before each main-frame navigation so per-site settings apply to the new page.
    func prepare(_ controller: WKUserContentController, for url: URL) {
        currentSite[ObjectIdentifier(controller)] = Self.site(for: url)
        install(on: controller)
    }

    private func install(on controller: WKUserContentController) {
        let key = ObjectIdentifier(controller)
        let wanted = Setup(
            blocking: isEnabled && pausedEntry(for: currentSite[key]) == nil,
            cookieRejection: isCookieRejectionEnabled,
            listGeneration: listGeneration
        )
        guard installed[key] != wanted else { return }
        installed[key] = wanted

        controller.removeAllContentRuleLists()
        controller.removeAllUserScripts()
        standardScripts.forEach(controller.addUserScript)
        if wanted.blocking {
            // autoconsent only rejects pop-ups it can see, so the cookie-banner
            // hiding list stands aside while it's on (it prehides known ones itself).
            for (name, list) in ruleLists where !(name == "cookies" && wanted.cookieRejection) {
                controller.add(list)
            }
            if let script = Self.youTubeScript {
                controller.addUserScript(script)
            }
        }
        if wanted.cookieRejection, let script = Self.autoconsentScript {
            controller.addUserScript(script)
        }
    }

    private func installEverywhere() {
        let live = controllers.allObjects
        let liveKeys = Set(live.map(ObjectIdentifier.init))
        installed = installed.filter { liveKeys.contains($0.key) }
        currentSite = currentSite.filter { liveKeys.contains($0.key) }
        live.forEach(install(on:))
    }

    // MARK: - Compilation

    private func loadLists() async {
        guard let store = WKContentRuleListStore.default() else {
            state = .ready
            return runReadyHandlers()
        }
        let available = Set(await store.availableIdentifiers() ?? [])
        // Lists that were retired or renamed would stay compiled forever.
        for retired in available where !Self.listNames.contains(where: { retired.hasPrefix("\($0)-") }) {
            try? await store.removeContentRuleList(forIdentifier: retired)
        }
        var lists: [(name: String, list: WKContentRuleList)] = []
        for name in Self.listNames {
            if let list = await ruleList(named: name, store: store, available: available) {
                lists.append((name, list))
            }
        }
        ruleLists = lists
        listGeneration += 1
        state = .ready
        installEverywhere()
        runReadyHandlers()
    }

    private func ruleList(named name: String, store: WKContentRuleListStore, available: Set<String>) async -> WKContentRuleList? {
        guard let text = FilterListUpdater.text(for: name) else {
            log.error("Missing filter list \(name, privacy: .public)")
            return nil
        }
        let identifier = "\(name)-v\(FilterListConverter.version)-\(Self.fingerprint(text))"
        // Earlier versions of this list: removed once the new one is in,
        // and kept blocking if it can't be built.
        let previous = available.filter { $0.hasPrefix("\(name)-") && $0 != identifier }.sorted()
        func replacingPrevious(with list: WKContentRuleList) async -> WKContentRuleList {
            for old in previous {
                try? await store.removeContentRuleList(forIdentifier: old)
            }
            return list
        }
        func fallingBack() async -> WKContentRuleList? {
            for old in previous {
                if let list = try? await store.contentRuleList(forIdentifier: old) { return list }
            }
            return nil
        }

        if available.contains(identifier), let cached = try? await store.contentRuleList(forIdentifier: identifier) {
            return await replacingPrevious(with: cached)
        }

        let started = ContinuousClock.now
        let output = await Task.detached(priority: .utility) {
            let output = FilterListConverter.convert(text)
            return (json: try? output.rules.encodedJSON(), count: output.rules.count, skipped: output.skipped)
        }.value
        guard let json = output.json else { return await fallingBack() }
        do {
            guard let list = try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) else {
                return await fallingBack()
            }
            log.info("Compiled \(name, privacy: .public): \(output.count) rules, \(output.skipped) skipped, \(started.duration(to: .now), privacy: .public)")
            return await replacingPrevious(with: list)
        } catch {
            let reason = (error as NSError).userInfo[NSHelpAnchorErrorKey] as? String ?? error.localizedDescription
            log.error("Couldn't compile \(name, privacy: .public): \(reason, privacy: .public)")
            return await fallingBack()
        }
    }

    private func runReadyHandlers() {
        let handlers = readyHandlers
        readyHandlers = []
        handlers.forEach { $0() }
    }

    private static let youTubeScript = pageScript(named: "youtube-ads")
    /// Runs in every frame: many consent pop-ups live in iframes.
    private static let autoconsentScript = pageScript(named: "autoconsent")

    /// A bundled script injected at document start into all frames, in the
    /// page's own JavaScript world (both scripts need the page's globals).
    private static func pageScript(named name: String) -> WKUserScript? {
        guard let url = BundledResource.url(named: name, extension: "js", in: "Scripts"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    private static func fingerprint(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}
