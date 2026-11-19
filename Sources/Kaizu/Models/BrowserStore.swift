import AppKit
import BrowserCore
import SwiftUI

/// One browser window: which space and tab it shows, its sidebar and
/// overlays, and the actions views call. What windows share lives in
/// `AppModel`. Split by concern across `BrowserStore+*.swift`: tabs, folders,
/// spaces, split, recents (⌃Tab, now playing), find, peek, external links,
/// privacy, command bar, window chrome, toasts.
@Observable
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
    var showingArchive = false
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
    @ObservationIgnored var toastTask: Task<Void, Never>?
    @ObservationIgnored var peekTask: Task<Void, Never>?

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

    var archive: [ArchivedTabRecord] {
        guard !isPrivate else { return [] }
        let profile = activeSpace.profile
        let spaceIDs = Set(spaces.filter { $0.profile === profile }.map(\.id))
        return app.archive.filter { spaceIDs.contains($0.spaceID) }
    }

    var closedTabs: [ClosedTab] {
        get { isPrivate ? privateClosedTabs : app.closedTabs }
        _modify {
            if isPrivate {
                yield &privateClosedTabs
            } else {
                yield &app.closedTabs
            }
        }
    }

    var settings: Settings { app.settings }
    var sounds: SoundPlayer { app.sounds }
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
}
