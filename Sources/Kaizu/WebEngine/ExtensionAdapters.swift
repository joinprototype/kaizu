import AppKit
import WebKit

/// The main window as extensions see it (`chrome.windows`): its tabs are the
/// active space's sidebar tabs.
@MainActor
final class MainWindowAdapter: NSObject, WKWebExtensionWindow {
    weak var store: BrowserStore?

    var tabs: [BrowserTab] { store?.activeSpace.allTabs ?? [] }

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
    private var extensionWindow: MainWindowAdapter? { store?.extensions.mainWindow }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { extensionWindow }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        extensionWindow?.tabs.firstIndex(of: self) ?? NSNotFound
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? { isLoaded ? webView : nil }

    func title(for context: WKWebExtensionContext) -> String? { displayTitle }

    func isPinned(for context: WKWebExtensionContext) -> Bool {
        !(store?.space(containing: self)?.today.contains(self) ?? false)
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
