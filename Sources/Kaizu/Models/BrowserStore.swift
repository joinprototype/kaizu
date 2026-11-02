import AppKit
import BrowserCore
import SwiftUI

enum CommandBarMode: Equatable {
    /// ⌘T: result opens in a new tab.
    case newTab
    /// ⌘L: result replaces the current tab's page.
    case currentTab
    /// The quick bar over another app: pages open in a little window.
    case quick
}

/// Where a moved or dragged tab lands. `before` is the id of the entry to
/// insert in front of; nil appends.
enum TabDestination {
    case favorites(before: UUID?)
    /// `folder` nil is the top level of the pinned section.
    case pinned(folder: Folder?, before: UUID?)
    case today(before: UUID?)

    var before: UUID? {
        switch self {
        case .favorites(let before), .pinned(_, let before), .today(let before): before
        }
    }
}

/// Working copy for the space editor sheet.
struct SpaceDraft: Identifiable {
    enum ProfileChoice: Hashable {
        case existing(UUID)
        case new
    }

    let id = UUID()
    var spaceID: UUID?
    var name: String
    var hue: Double
    var symbol: String
    var profile: ProfileChoice
    var appearance = Space.Appearance.auto
}

/// A short message at the bottom of the window, optionally with Undo.
struct Toast: Identifiable {
    let id = UUID()
    var message: String
    var symbol: String?
    var undo: (@MainActor () -> Void)?
    var actionTitle = "Undo"
}

struct ClosedTab {
    let spaceID: UUID
    let record: TabRecord
}

/// One browser window: which space and tab it shows, its sidebar and
/// overlays, and the actions views call. What windows share lives in
/// `AppModel`. Split by concern across `BrowserStore+*.swift`: tabs, spaces,
/// split, recents (⌃Tab, now playing), find, peek, external links, privacy.
@MainActor @Observable
final class BrowserStore {
    unowned let app: AppModel
    /// Set for a private window: the only space it sees, and nothing else sees it.
    let privateSpace: Space?
    var activeSpaceID: UUID {
        didSet { if activeSpaceID != oldValue { updateWindowAppearance() } }
    }
    /// The tab each space shows in this window, by space. Each window keeps
    /// its own, and no two keep the same page: see `setSelected`.
    private(set) var selectedTabIDs: [UUID: UUID]
    var isSidebarVisible: Bool
    var isSidebarPeeking = false
    var sidebarWidth: Double
    var commandBar: CommandBarMode?
    var find: FindState?
    /// A link preview over the page (see BrowserStore+Peek).
    var peek: BrowserTab?
    /// The selected tab's article in Reader (see BrowserStore+Reader).
    var reader: ReaderArticle?
    /// The tab whose page is being captured (see BrowserStore+Capture).
    var capture: UUID?
    var tabSwitcher: TabSwitcherState?
    var spaceDraft: SpaceDraft?
    /// Which way the last space switch went, so the sidebar slides the right way.
    var spaceSwitchForward = true
    /// How far the sidebar's contents follow the fingers during a space swipe.
    var spaceSwipeOffset: CGFloat = 0
    /// The neighbor a swipe is uncovering, shown beside the active space.
    var revealingSpaceID: UUID?
    /// The space just switched away from, still sliding out.
    var leavingSpaceID: UUID?
    /// A folder that was just created and should open in rename mode.
    var renamingFolderID: UUID?
    /// The tab whose sidebar row is being renamed.
    var renamingTabID: UUID?
    var toast: Toast?
    /// Briefly true after Copy Link, so the address pill can flash "Copied".
    var didCopyLink = false

    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored var windowController: BrowserWindowController?
    /// Where the session last had this window; nil lets the system place it.
    @ObservationIgnored let savedFrame: String?
    /// This window as extensions see it.
    @ObservationIgnored private(set) lazy var extensionWindow = MainWindowAdapter(store: self)
    /// The peek card is growing into a tab (see expandPeek).
    var isPeekExpanding = false
    /// The tab whose items are being picked to hide.
    var hidingItemsTabID: UUID?
    /// The color being tried in the space editor, shown on the window.
    var previewTheme: Theme?
    /// Likewise its light/dark choice.
    var previewAppearance: Space.Appearance? {
        didSet { updateWindowAppearance() }
    }
    /// ⌘S while the sidebar peeks: it docks where it is instead of one
    /// sidebar sliding out while another slides in.
    var sidebarDocksFromPeek = false
    /// Horizontal travel of the current two-finger swipe; nil once it switched spaces.
    @ObservationIgnored var spaceSwipeTravel: CGFloat?
    /// The swipe's recent (time, travel), for its speed when the fingers lift.
    @ObservationIgnored var spaceSwipeSamples: [(time: TimeInterval, travel: CGFloat)] = []
    /// Counts swipes, so one's spring-back can't tidy up after the next.
    @ObservationIgnored var spaceSwipeGeneration = 0
    /// Removed with the window; each store's only look at its own events.
    @ObservationIgnored private var eventMonitors: [Any] = []
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var peekTask: Task<Void, Never>?

    /// What a private window closed, for ⇧⌘T there; gone with the window.
    @ObservationIgnored private var privateClosedTabs: [ClosedTab] = []

    init(app: AppModel, record: WindowRecord, privateSpace: Space? = nil) {
        self.app = app
        self.privateSpace = privateSpace
        activeSpaceID = privateSpace?.id ?? app.spaces.first { $0.id == record.activeSpaceID }?.id ?? app.spaces[0].id
        selectedTabIDs = record.selectedTabIDs
        isSidebarVisible = record.isSidebarVisible
        sidebarWidth = record.sidebarWidth
        savedFrame = record.frame
        installEscapeMonitor()
        installSplitFocusMonitor()
        installSpaceSwipeMonitor()
        installTabSwitcherMonitor()
    }

    /// The window is gone for good. Its tabs stay in their spaces.
    func tearDown() {
        endHidingItems()
        // What it showed was in use until now, or the next sweep would
        // archive a tab that's been open here for days.
        let now = Date()
        spaces.compactMap(selectedTab(in:)).forEach { $0.lastActiveAt = now }
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors = []
        peek?.discard()
        peek = nil
        app.extensions.didClose(self)
        // Its views let go of the pages, so another window can take them.
        window?.contentView = nil
        windowController = nil
        if let privateSpace {
            app.discard(privateSpace.allTabs)
            DownloadManager.shared.forget(privateSpace.profile.dataStore)
            UtilityWindows.closeBrokenSiteReport(in: privateSpace.profile)
        }
    }

    /// For this window's events only.
    func addEventMonitor(matching mask: NSEvent.EventTypeMask, handler: @escaping (BrowserStore, NSEvent) -> NSEvent?) {
        let monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return handler(self, event)
        }
        if let monitor {
            eventMonitors.append(monitor)
        }
    }

    // MARK: - Shared by every window

    var isPrivate: Bool { privateSpace != nil }

    var profiles: [Profile] {
        get { privateSpace.map { [$0.profile] } ?? app.profiles }
        set { app.profiles = newValue }
    }

    var spaces: [Space] {
        get { privateSpace.map { [$0] } ?? app.spaces }
        set { app.spaces = newValue }
    }

    var archive: [ArchivedTabRecord] { isPrivate ? [] : app.archive }

    var closedTabs: [ClosedTab] {
        get { isPrivate ? privateClosedTabs : app.closedTabs }
        set {
            if isPrivate {
                privateClosedTabs = newValue
            } else {
                app.closedTabs = newValue
            }
        }
    }

    var settings: Settings { app.settings }
    var contentBlocker: ContentBlocker { app.contentBlocker }
    var extensions: ExtensionHost { app.extensions }
    var history: HistoryStore? { app.history }

    func scheduleSave() {
        app.scheduleSave()
    }

    // MARK: - What this window shows

    var activeSpace: Space {
        spaces.first { $0.id == activeSpaceID } ?? spaces[0]
    }

    var selectedTab: BrowserTab? {
        selectedTab(in: activeSpace)
    }

    func selectedTab(in space: Space) -> BrowserTab? {
        selectedTabIDs[space.id].flatMap(space.tab(id:))
    }

    /// The one place selections change. What this window takes, with the
    /// rest of its split, no other window keeps for when it comes back.
    func setSelected(_ tab: BrowserTab?, in space: Space) {
        selectedTabIDs[space.id] = tab?.id
        guard let tab else { return }
        let shown = space.panes(with: tab)
        shown.forEach { $0.markNotificationsRead() }
        let panes = Set(shown.map(\.id))
        for other in app.stores where other !== self && other.selectedTabIDs.values.contains(where: panes.contains) {
            other.selectedTabIDs = other.selectedTabIDs.filter { !panes.contains($0.value) }
        }
    }

    /// The panes on screen.
    var shownTabs: [BrowserTab] {
        selectedTab.map(activeSpace.panes(with:)) ?? []
    }

    /// Pages on screen in other windows, which this one can't have.
    var tabsElsewhere: Set<BrowserTab> {
        Set(app.stores.filter { $0 !== self }.flatMap(\.shownTabs))
    }

    func isShowing(_ tab: BrowserTab) -> Bool {
        tab === peek || shownTabs.contains(tab)
    }

    var record: WindowRecord {
        WindowRecord(
            activeSpaceID: activeSpaceID, isSidebarVisible: isSidebarVisible, sidebarWidth: sidebarWidth,
            selectedTabIDs: selectedTabIDs, frame: window?.frameDescriptor ?? savedFrame
        )
    }

    func focusWebView() {
        // Deferred so SwiftUI has attached the web view to the window first.
        Task { [weak self] in
            guard let webView = self?.selectedTab?.webView, let window = webView.window else { return }
            if !(window.firstResponder is NSTextView) {
                window.makeFirstResponder(webView)
            }
        }
    }

    /// ⌘N: a window on this space, asking where to go first. From a
    /// private window, an ordinary one.
    func openNewWindow() {
        app.openWindow().showCommandBar(.newTab)
    }

    /// ⇧⌘P.
    func openPrivateWindow() {
        app.openPrivateWindow().showCommandBar(.newTab)
    }

    // MARK: - Command bar

    func showCommandBar(_ mode: CommandBarMode) {
        window?.makeKeyAndOrderFront(nil)
        withAnimation(Motion.pop) {
            commandBar = mode
        }
    }

    func dismissCommandBar() {
        withAnimation(Motion.snap) {
            commandBar = nil
        }
        focusWebView()
    }

    func perform(_ suggestion: Suggestion, mode: CommandBarMode) {
        if mode == .quick {
            app.quickBar?.hide()
            // From the quick bar, pages get a little window; tabs, commands
            // and the archive need the main window.
            switch suggestion {
            case .command, .tab, .archived:
                window?.makeKeyAndOrderFront(nil)
                NSApp.activate()
            default: break
            }
        } else {
            withAnimation(Motion.snap) {
                commandBar = nil
            }
        }
        switch suggestion {
        case .answer(let answer):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(answer.answer, forType: .string)
            // Over another app, copying is the whole point: nothing comes forward.
            guard mode != .quick else { return }
            showToast("Copied \(answer.answer)")
            focusWebView()
        case .shortcut(let shortcut, let query):
            if let url = shortcut.url(for: query) {
                open(url, mode: mode)
            }
        case .command(let command):
            command.perform()
        case .tab(let tab):
            select(tab)
        case .archived(let archived):
            reopen(archived)
        case .history(let entry):
            open(entry.url, mode: mode)
        case .url(let url):
            open(url, mode: mode)
        case .search(let query):
            if let url = settings.searchEngine.searchURL(for: query) {
                open(url, mode: mode)
            }
        }
    }

    private func open(_ url: URL, mode: CommandBarMode) {
        switch mode {
        case .currentTab where selectedTab != nil:
            selectedTab?.load(url)
            focusWebView()
        case .quick:
            openLittleWindow(url)
            NSApp.activate()
        default:
            openTab(url)
        }
    }

    // MARK: - Window chrome

    func toggleSidebar() {
        // Views keep the transition they last rendered with, so a change of
        // transition has to render before the sidebar moves: then toggle.
        let docksFromPeek = !isSidebarVisible && isSidebarPeeking
        if sidebarDocksFromPeek != docksFromPeek {
            sidebarDocksFromPeek = docksFromPeek
            Task { @MainActor [weak self] in self?.toggleSidebar() }
            return
        }
        withAnimation(Motion.snap) {
            isSidebarVisible.toggle()
            isSidebarPeeking = false
        } completion: { [weak self] in
            self?.sidebarDocksFromPeek = false
        }
        updateWindowChrome()
        scheduleSave()
    }

    /// Opens after a short hover intent (so flicking the pointer to the
    /// window edge doesn't trigger it) and closes after a grace period (so a
    /// small overshoot past the sidebar doesn't snap it away).
    func setSidebarPeeking(_ peeking: Bool) {
        // A late "left" from a sidebar that already closed mustn't cancel a reopen.
        if !peeking, !isSidebarPeeking { return }
        peekTask?.cancel()
        guard !isSidebarVisible, peeking != isSidebarPeeking else { return }
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(peeking ? 120 : 280))
            guard !Task.isCancelled, let self, !self.isSidebarVisible else { return }
            self.applySidebarPeeking(peeking)
        }
    }

    /// The pointer left the window edge before the peek opened.
    func cancelSidebarPeek() {
        guard !isSidebarPeeking else { return }
        peekTask?.cancel()
    }

    private func applySidebarPeeking(_ peeking: Bool) {
        withAnimation(Motion.snap) {
            isSidebarPeeking = peeking
        }
        updateWindowChrome()
    }

    /// The active space's light or dark (or the system's), for the whole
    /// window, pages included.
    func updateWindowAppearance() {
        // Also runs while a session is being applied, when spaces may be empty.
        guard let window else { return }
        let appearance: NSAppearance? = switch previewAppearance ?? spaces.first(where: { $0.id == activeSpaceID })?.appearance ?? .auto {
        case .auto: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        // Setting it redraws the whole window, so only when it changes
        // (most space switches keep it).
        guard window.appearance?.name != appearance?.name else { return }
        window.appearance = appearance
    }

    /// Traffic lights live in the sidebar; they fade with it when it's
    /// collapsed (and are hidden after, so they can't be clicked unseen).
    func updateWindowChrome(animated: Bool = true) {
        let hidden = !isSidebarVisible && !isSidebarPeeking
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window?.standardWindowButton(kind) else { continue }
            if !hidden { button.isHidden = false }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animated ? 0.18 : 0
                button.animator().alphaValue = hidden ? 0 : 1
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.isSidebarVisible, !self.isSidebarPeeking else { return }
                    button.isHidden = true
                }
            }
        }
    }

    func showToast(
        _ message: String,
        symbol: String? = nil,
        undo: (@MainActor () -> Void)? = nil,
        actionTitle: String = "Undo",
        lasts: Duration? = nil
    ) {
        toastTask?.cancel()
        // The same kind of toast again (zoom steps) changes in place.
        if var current = toast, current.symbol == symbol, current.undo == nil, undo == nil {
            current.message = message
            withAnimation(Motion.snap) { toast = current }
        } else {
            withAnimation(Motion.pop) {
                toast = Toast(message: message, symbol: symbol, undo: undo, actionTitle: actionTitle)
            }
        }
        toastTask = Task { [weak self] in
            // Leave time to reach for Undo.
            try? await Task.sleep(for: lasts ?? .seconds(undo == nil ? 1.6 : 4))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.snap) {
                self?.toast = nil
            }
        }
    }

    func undoToast() {
        let undo = toast?.undo
        withAnimation(Motion.snap) {
            toast = nil
        }
        undo?()
    }
}
