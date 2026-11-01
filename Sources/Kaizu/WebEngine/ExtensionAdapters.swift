import AppKit
import WebKit

/// A browser window as extensions see it (`chrome.windows`): its tabs are
/// the active space's sidebar tabs. Windows on the same space list the same
/// sidebar, but extensions expect a tab in one window: the one showing it,
/// else the first on its space.
@MainActor
final class MainWindowAdapter: NSObject, WKWebExtensionWindow {
    weak var store: BrowserStore?

    init(store: BrowserStore) {
        self.store = store
    }

    var tabs: [BrowserTab] {
        guard let store else { return [] }
        let space = store.activeSpace
        let isFirstOnSpace = store === store.app.stores.first { $0.activeSpaceID == space.id }
        // Favorites are on every space of a profile.
        let isFirstOnProfile = store === store.app.stores.first { $0.activeSpace.profile === space.profile }
        let favorites = Set(space.profile.favorites)
        return space.allTabs.filter { tab in
            guard let showing = store.app.store(showing: tab) else {
                return favorites.contains(tab) ? isFirstOnProfile : isFirstOnSpace
            }
            return showing === store
        }
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { tabs }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { store?.selectedTab }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window = store?.window else { return .normal }
        if window.isMiniaturized { return .minimized }
        return window.styleMask.contains(.fullScreen) ? .fullscreen : .normal
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool { false }

    func frame(for context: WKWebExtensionContext) -> CGRect { store?.window?.frame ?? .null }

    func screenFrame(for context: WKWebExtensionContext) -> CGRect { store?.window?.screen?.frame ?? .null }

    func focus(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        store?.window?.makeKeyAndOrderFront(nil)
        completionHandler(nil)
    }
}

/// A tab as extensions see it (`chrome.tabs`).
extension BrowserTab: WKWebExtensionTab {
    private var extensionWindow: MainWindowAdapter? {
        guard let app else { return nil }
        return (app.store(showing: self) ?? app.stores.first { $0.activeSpace.allTabs.contains(self) })?.extensionWindow
    }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { extensionWindow }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        extensionWindow?.tabs.firstIndex(of: self) ?? NSNotFound
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? { isLoaded ? webView : nil }

    func title(for context: WKWebExtensionContext) -> String? { displayTitle }

    func isPinned(for context: WKWebExtensionContext) -> Bool {
        !(app?.spaces.contains { $0.today.contains(self) } ?? false)
    }

    func isPlayingAudio(for context: WKWebExtensionContext) -> Bool { isPlayingMedia }

    func isMuted(for context: WKWebExtensionContext) -> Bool { isMuted }

    func setMuted(_ muted: Bool, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if muted != isMuted { toggleMute() }
        completionHandler(nil)
    }

    func url(for context: WKWebExtensionContext) -> URL? { url }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !isLoading }

    func isSelected(for context: WKWebExtensionContext) -> Bool { store?.selectedTab === self }

    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        load(url)
        completionHandler(nil)
    }

    func reload(fromOrigin: Bool, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        reload(fromOrigin: fromOrigin)
        completionHandler(nil)
    }

    func goBack(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        goBack()
        completionHandler(nil)
    }

    func goForward(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        goForward()
        completionHandler(nil)
    }

    func activate(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        store?.select(self)
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        store?.close(self)
        completionHandler(nil)
    }
}
