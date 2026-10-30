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

/// App state and the actions views call. Split by concern across
/// `BrowserStore+*.swift`: tabs, spaces, split, recents (⌃Tab, now playing),
/// archive, hibernation, find, peek, external links, persistence, privacy.
@MainActor @Observable
final class BrowserStore {
    var profiles: [Profile] = []
    var spaces: [Space] = []
    var activeSpaceID = UUID() {
        didSet { if activeSpaceID != oldValue { updateWindowAppearance() } }
    }
    var isSidebarVisible = true
    var isSidebarPeeking = false
    var sidebarWidth = 248.0
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
    var toast: Toast?
    /// Briefly true after Copy Link, so the address pill can flash "Copied".
    var didCopyLink = false
    /// Today tabs swept away after sitting unused, newest first.
    var archive: [ArchivedTabRecord] = []

    let settings = Settings()
    let contentBlocker = ContentBlocker()
    let extensions = ExtensionHost()
    let history = try? HistoryStore(fileURL: AppPaths.support.appending(path: "history.sqlite"))

    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored var closedTabs: [ClosedTab] = []
    @ObservationIgnored var littleWindows: [LittleWindowController] = []
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
    @ObservationIgnored var quickBar: QuickBarController?
    @ObservationIgnored var quickBarHotKey: GlobalHotKey?
    /// What Spotlight was last given (see BrowserStore+Spotlight); nil
    /// until the first update of this launch.
    @ObservationIgnored var spotlightSignature: [String]?
    @ObservationIgnored var spotlightIdentifiers: Set<String> = []
    @ObservationIgnored var spotlightUpdate: Task<Void, Never>?
    @ObservationIgnored var menuCommandCache: (time: Date, commands: [PaletteCommand])?
    /// What the command bar has learned you pick, per profile.
    @ObservationIgnored var choices: [UUID: ChoiceMemory] = [:]
    /// Another app already holds the quick bar's shortcut.
    var isQuickBarKeyTaken = false
    /// Horizontal travel of the current two-finger swipe; nil once it switched spaces.
    @ObservationIgnored var spaceSwipeTravel: CGFloat?
    /// The swipe's recent (time, travel), for its speed when the fingers lift.
    @ObservationIgnored var spaceSwipeSamples: [(time: TimeInterval, travel: CGFloat)] = []
    /// Counts swipes, so one's spring-back can't tidy up after the next.
    @ObservationIgnored var spaceSwipeGeneration = 0
    @ObservationIgnored var memoryPressureSource: DispatchSourceMemoryPressure?
    @ObservationIgnored var saveTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var peekTask: Task<Void, Never>?

    init() {
        contentBlocker.standardScripts = [MediaEvents.script]
        contentBlocker.start()
        extensions.store = self
        Task {
            await extensions.loadInstalled()
            spaces.flatMap(\.allTabs).forEach { $0.reopenExtensionPage() }
        }
        restore()
        loadChoices()
        startArchiving()
        startHibernating()
        startMediaMonitoring()
        installEscapeMonitor()
        installSplitFocusMonitor()
        installSpaceSwipeMonitor()
        installTabSwitcherMonitor()
        DownloadManager.shared.onFinish = { [weak self] filename in
            self?.showToast("Downloaded \(filename)")
        }
    }

    var activeSpace: Space {
        spaces.first { $0.id == activeSpaceID } ?? spaces[0]
    }

    var selectedTab: BrowserTab? {
        activeSpace.selectedTab
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
            quickBar?.hide()
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
