import OSLog
import WebKit

/// Built-in ad, tracker and cookie-banner blocking, YouTube ad removal, and
/// automatic rejection of cookie consent pop-ups (DuckDuckGo's autoconsent,
/// see `AutoconsentBridge`).
///
/// Filter lists are converted to WebKit content rules, compiled once (see
/// `RuleListCompiler`) and cached by WebKit. Each tab gets its own user
/// content controller so blocking can be paused per site without recompiling
/// anything.
@Observable
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
    private static let enabledKey = "contentBlockingEnabled"
    private static let cookieRejectionKey = "cookiePopupRejectionEnabled"
    private static let pausedSitesKey = "blockingPausedSites"

    let importedLists = ImportedRuleLists(directory: AppPaths.support.appending(path: "ImportedRules", directoryHint: .isDirectory))
    private(set) var state: State = .idle
    private(set) var isEnabled: Bool
    private(set) var isCookieRejectionEnabled: Bool
    /// Sites (and their subdomains) where the user turned blocking off.
    private(set) var pausedSites: Set<String>
    /// Each private window may override ordinary blocking preferences for its own sites.
    private var privateOverrides: [UUID: [String: Bool]] = [:]
    private struct Page {
        let privateID: UUID?
        var site: String?
    }

    @ObservationIgnored private var ruleLists: [(name: String, list: WKContentRuleList)] = []
    @ObservationIgnored private var listGeneration = 0
    @ObservationIgnored private let controllers = NSHashTable<WKUserContentController>.weakObjects()
    @ObservationIgnored private var installed: [ObjectIdentifier: Setup] = [:]
    @ObservationIgnored private var pages: [ObjectIdentifier: Page] = [:]
    @ObservationIgnored private var waitingNavigations: [(url: URL, privateID: UUID?, proceed: @MainActor () -> Void)] = []
    /// Scripts every page gets whatever the blocking settings; reinstalls
    /// (which clear a controller's scripts) put them back.
    @ObservationIgnored var standardScripts: [WKUserScript] = []
    @ObservationIgnored private let log = Logger(subsystem: Log.subsystem, category: "ContentBlocker")

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        isCookieRejectionEnabled = defaults.object(forKey: Self.cookieRejectionKey) as? Bool ?? true
        pausedSites = Set(defaults.stringArray(forKey: Self.pausedSitesKey) ?? [])
    }

    func start() {
        guard state == .idle else { return }
        state = .preparing
        AutoconsentBridge.warmUp()
        importedLists.didChange = { [weak self] in self?.rulesDidChange() }
        Task {
            await importedLists.restore()
            await loadLists()
            while true {
                await refreshLists()
                try? await Task.sleep(for: FilterListUpdater.checkEvery)
            }
        }
    }

    /// Fetches newer lists if they're due. Open pages keep the rules they
    /// loaded with; their next load gets the new ones.
    func refreshLists() async {
        if await FilterListUpdater.updateIfDue() {
            await loadLists()
        }
    }

    /// Hold network navigation while WebKit prepares the bundled rules on first launch.
    /// Local pages and sites the user has exempted can open immediately.
    func whenReady(for url: URL, privateID: UUID? = nil, proceed: @escaping @MainActor () -> Void) {
        if needsRules(for: url, privateID: privateID) {
            waitingNavigations.append((url, privateID, proceed))
        } else {
            proceed()
        }
    }

    private func needsRules(for url: URL, privateID: UUID?) -> Bool {
        state != .ready && isEnabled && (url.scheme == "https" || url.scheme == "http") && !isPaused(on: url, privateID: privateID)
    }

    // MARK: - Settings

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        installEverywhere()
    }

    func setCookieRejectionEnabled(_ enabled: Bool) {
        isCookieRejectionEnabled = enabled
        defaults.set(enabled, forKey: Self.cookieRejectionKey)
        installEverywhere()
    }

    func isPaused(on url: URL?, privateID: UUID?) -> Bool {
        isPaused(site: url.flatMap(Self.site(for:)), privateID: privateID)
    }

    @discardableResult
    func togglePause(on url: URL, privateID: UUID?) -> Bool {
        guard let site = Self.site(for: url) else { return false }
        if let privateID {
            let pause = !isPaused(site: site, privateID: privateID)
            privateOverrides[privateID]?[site] = nil
            // Back to the inherited setting? Follow later regular changes again.
            if isPaused(site: site, privateID: privateID) != pause {
                privateOverrides[privateID, default: [:]][site] = pause
            }
            installEverywhere()
        } else if let entry = pausedEntry(for: site) {
            resume(entry)
        } else {
            updatePausedSites { _ = $0.insert(site) }
        }
        return isPaused(site: site, privateID: privateID)
    }

    func resume(_ site: String) {
        updatePausedSites { _ = $0.remove(site) }
    }

    func forgetPrivateOverrides(for id: UUID) {
        privateOverrides.removeValue(forKey: id)
    }

    private func updatePausedSites(_ change: (inout Set<String>) -> Void) {
        change(&pausedSites)
        defaults.set(pausedSites.sorted(), forKey: Self.pausedSitesKey)
        installEverywhere()
    }

    static func site(for url: URL) -> String? {
        guard let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func isPaused(site: String?, privateID: UUID?) -> Bool {
        guard let site else { return false }
        if let privateID, let overrides = privateOverrides[privateID] {
            var domain = site[...]
            while !domain.isEmpty {
                if let paused = overrides[String(domain)] { return paused }
                guard let dot = domain.firstIndex(of: ".") else { break }
                domain = domain.suffix(from: domain.index(after: dot))
            }
        }
        return pausedEntry(for: site) != nil
    }

    private func pausedEntry(for site: String) -> String? {
        pausedSites.first { site == $0 || site.hasSuffix("." + $0) }
    }

    // MARK: - Tabs

    /// A fresh controller for a new web view, with blocking installed.
    func makeUserContentController(privateID: UUID?) -> WKUserContentController {
        let controller = WKUserContentController()
        let key = ObjectIdentifier(controller)
        // Identifiers of deallocated controllers can be reused.
        installed[key] = nil
        pages[key] = Page(privateID: privateID)
        controllers.add(controller)
        AutoconsentBridge.install(on: controller)
        install(on: controller)
        return controller
    }

    /// Call before each main-frame navigation so per-site settings apply to the new page.
    func prepare(_ controller: WKUserContentController, for url: URL) {
        pages[ObjectIdentifier(controller)]?.site = Self.site(for: url)
        install(on: controller)
    }

    private func install(on controller: WKUserContentController) {
        let key = ObjectIdentifier(controller)
        let page = pages[key]
        let wanted = Setup(
            blocking: isEnabled && !isPaused(site: page?.site, privateID: page?.privateID),
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
            importedLists.install(on: controller)
            if let script = Self.youTubeScript {
                controller.addUserScript(script)
            }
        }
        if wanted.cookieRejection, let script = AutoconsentBridge.script {
            controller.addUserScript(script)
        }
    }

    private func rulesDidChange() {
        listGeneration += 1
        installEverywhere()
    }

    private func installEverywhere() {
        let live = controllers.allObjects
        let liveKeys = Set(live.map(ObjectIdentifier.init))
        installed = installed.filter { liveKeys.contains($0.key) }
        pages = pages.filter { liveKeys.contains($0.key) }
        live.forEach(install(on:))
        resumeReadyNavigations()
    }

    // MARK: - Compilation

    private func loadLists() async {
        guard let store = WKContentRuleListStore.default() else {
            state = .ready
            return rulesDidChange()
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
        state = .ready
        rulesDidChange()
    }

    private func ruleList(named name: String, store: WKContentRuleListStore, available: Set<String>) async -> WKContentRuleList? {
        guard let text = FilterListUpdater.text(for: name) else {
            log.error("Missing filter list \(name, privacy: .public)")
            return nil
        }
        let identifier = RuleListCompiler.identifier(for: name, text: text)
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

        var list: WKContentRuleList?
        if await RuleListCompiler.compileInHelper(name) {
            list = try? await store.contentRuleList(forIdentifier: identifier)
        }
        if list == nil {
            // Blocking matters more than the memory a compile here would keep.
            log.error("Compiling \(name, privacy: .public) without the helper")
            list = await RuleListCompiler.compile(name, text: text, into: store)
        }
        if let list {
            return await replacingPrevious(with: list)
        }
        return await fallingBack()
    }

    private func resumeReadyNavigations() {
        let pending = waitingNavigations
        waitingNavigations = []
        for (url, privateID, proceed) in pending {
            whenReady(for: url, privateID: privateID, proceed: proceed)
        }
    }

    private static let youTubeScript = pageScript(named: "youtube-ads")

    /// A bundled script injected at document start into all frames, in the
    /// page's own JavaScript world (it needs the page's globals).
    private static func pageScript(named name: String) -> WKUserScript? {
        guard let url = BundledResource.url(named: name, extension: "js", in: "Scripts"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
}
