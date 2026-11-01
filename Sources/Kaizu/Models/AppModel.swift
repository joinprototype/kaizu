import AppKit
import BrowserCore
import Foundation

/// What every window shares: profiles, spaces and their tabs, the archive
/// and the services behind them. What differs between windows (which space
/// and tab each shows, its sidebar, its overlays) is its `BrowserStore`.
/// Split by concern across `AppModel+*.swift`.
@MainActor @Observable
final class AppModel {
    var profiles: [Profile] = []
    var spaces: [Space] = []
    /// Today tabs swept away after sitting unused, newest first.
    var archive: [ArchivedTabRecord] = []
    /// One per browser window, oldest first. Never empty: closing the last
    /// window only hides it, ready for a click on the Dock.
    private(set) var stores: [BrowserStore] = []
    /// Another app already holds the quick bar's shortcut.
    var isQuickBarKeyTaken = false

    let settings = Settings()
    let contentBlocker = ContentBlocker()
    let extensions = ExtensionHost()
    let history = try? HistoryStore(fileURL: AppPaths.support.appending(path: "history.sqlite"))

    @ObservationIgnored var closedTabs: [ClosedTab] = []
    @ObservationIgnored var littleWindows: [LittleWindowController] = []
    @ObservationIgnored var quickBar: QuickBarController?
    @ObservationIgnored var quickBarHotKey: GlobalHotKey?
    /// What Spotlight was last given (see AppModel+Spotlight); nil until the
    /// first update of this launch.
    @ObservationIgnored var spotlightSignature: [String]?
    @ObservationIgnored var spotlightIdentifiers: Set<String> = []
    @ObservationIgnored var spotlightUpdate: Task<Void, Never>?
    @ObservationIgnored var menuCommandCache: (time: Date, commands: [PaletteCommand])?
    /// What the command bar has learned you pick, per profile.
    @ObservationIgnored var choices: [UUID: ChoiceMemory] = [:]
    @ObservationIgnored var memoryPressureSource: DispatchSourceMemoryPressure?
    @ObservationIgnored var saveTask: Task<Void, Never>?
    @ObservationIgnored private weak var lastKeyStore: BrowserStore?

    init() {
        contentBlocker.standardScripts = [MediaEvents.script]
        contentBlocker.start()
        extensions.app = self
        Task {
            await extensions.loadInstalled()
            spaces.flatMap(\.allTabs).forEach { $0.reopenExtensionPage() }
        }
        restore()
        loadChoices()
        startArchiving()
        startHibernating()
        startMediaMonitoring()
        DownloadManager.shared.onFinish = { [weak self] filename in
            self?.front.showToast("Downloaded \(filename)")
        }
    }

    /// The window menus, shortcuts and other apps' links act on: the key
    /// one, or the last that was.
    var front: BrowserStore {
        get { lastKeyStore ?? stores[0] }
        set { lastKeyStore = newValue }
    }

    func addWindow(_ record: WindowRecord) -> BrowserStore {
        let store = BrowserStore(app: self, record: record)
        stores.append(store)
        extensions.didOpen(store)
        return store
    }

    /// The window `tab` is on screen in, if any: a tab's page can only be in
    /// one place at a time.
    func store(showing tab: BrowserTab) -> BrowserStore? {
        stores.first { $0.isShowing(tab) }
    }

    /// Brings Kaizu's window forward, building the windows from the session
    /// on first use.
    func showFront() {
        for store in stores where store.windowController == nil {
            BrowserWindowController(store: store).showWindow(nil)
        }
        front.window?.makeKeyAndOrderFront(nil)
    }

    /// ⌘N: another window on the same space, with nothing selected yet.
    @discardableResult
    func openWindow(on space: Space? = nil) -> BrowserStore {
        let from = front
        let store = addWindow(WindowRecord(
            activeSpaceID: (space ?? from.activeSpace).id,
            isSidebarVisible: from.isSidebarVisible, sidebarWidth: from.sidebarWidth
        ))
        let controller = BrowserWindowController(store: store)
        if let window = controller.window, let frontWindow = from.window, !frontWindow.styleMask.contains(.fullScreen) {
            window.setFrame(frontWindow.frame, display: false)
            window.cascadeTopLeft(from: frontWindow.cascadeTopLeft(from: .zero))
        }
        controller.showWindow(nil)
        front = store
        scheduleSave()
        return store
    }

    /// A window closed by the user. The last one stays, hidden, so a click
    /// on the Dock brings back what it showed.
    func windowDidClose(_ store: BrowserStore) {
        guard stores.count > 1 else { return }
        let wasFirst = store === stores[0]
        stores.removeAll { $0 === store }
        store.tearDown()
        if lastKeyStore === store {
            lastKeyStore = stores.last
        }
        if wasFirst {
            stores[0].windowController?.takeAutosavedFrame()
        }
        scheduleSave()
    }

    func windowDidBecomeKey(_ store: BrowserStore) {
        lastKeyStore = store
        extensions.didFocus(store)
    }
}
