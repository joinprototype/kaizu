import AppKit
import WebKit

/// A tab's web view: where its right-click menu can be changed.
final class PageWebView: WKWebView {
    weak var tab: BrowserTab?
    #if DEBUG
    /// Hands the QA hook each menu as it opens.
    static var onContextMenu: ((NSMenu) -> Void)?
    #endif

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        tab?.adapt(menu)
        #if DEBUG
        Self.onContextMenu?(menu)
        #endif
    }
}

/// Where a link picked from the page's menu goes, other than a new tab.
enum LinkDestination {
    case split, newWindow, privateWindow
}

/// WebKit's menu is written for a browser of windows, and searches with the
/// system's engine. Its items have no public identifiers, so this goes by the
/// names WebKit gives them; an item it renames just stays as WebKit made it.
extension BrowserTab {
    func adapt(_ menu: NSMenu) {
        func item(_ name: String) -> NSMenuItem? {
            menu.items.first { $0.identifier?.rawValue == "WKMenuItemIdentifier\(name)" }
        }
        // What opens in a new window here is a tab.
        for name in ["OpenLinkInNewWindow", "OpenImageInNewWindow", "OpenMediaInNewWindow", "OpenFrameInNewWindow"] {
            if let opener = item(name) {
                opener.title = opener.title.replacingOccurrences(of: "New Window", with: "New Tab")
            }
        }
        if let opener = item("OpenLinkInNewWindow") {
            addDestinations(after: opener, in: menu)
        }
        if let search = item("SearchWeb") {
            replace(search, in: menu)
        }
        if let reload = item("Reload"), let url {
            menu.insertItem(NSSharingServicePicker(items: [url]).standardShareMenuItem, at: menu.index(of: reload) + 1)
        }
    }

    /// Each one fires WebKit's own item, which is what knows the link, and
    /// `createWebViewWith` sends it here instead of to a tab.
    private func addDestinations(after opener: NSMenuItem, in menu: NSMenu) {
        guard let store else { return }
        var destinations: [(String, LinkDestination)] = []
        if store.isShowing(self), store.peek !== self, store.activeSpace.splitTabs.count < BrowserStore.maxSplitPanes {
            destinations.append(("Open Link in Split View", .split))
        }
        if !profile.isPrivate {
            destinations.append(("Open Link in New Window", .newWindow))
            destinations.append(("Open Link in Private Window", .privateWindow))
        }
        let start = menu.index(of: opener) + 1
        for (offset, destination) in destinations.enumerated() {
            let item = ActionMenuItem(destination.0) { [weak self, weak opener] in
                guard let self, let opener, let action = opener.action else { return }
                linkDestination = destination.1
                NSApp.sendAction(action, to: opener.target, from: opener)
                // If WebKit never asks, a popup later mustn't go there.
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    self.linkDestination = nil
                }
            }
            menu.insertItem(item, at: start + offset)
        }
    }

    /// Uses your search engine, not the system's. A selection inside a frame
    /// can't be read from here, so that's left to WebKit's item, kept hidden.
    private func replace(_ search: NSMenuItem, in menu: NSMenu) {
        guard let engine = app?.settings.searchEngine else { return }
        let own = ActionMenuItem("Search with \(engine.name)") { [weak self, weak search] in
            guard let self else { return }
            Task {
                let selection = (try? await self.webView.evaluateJavaScript("String(getSelection())", contentWorld: .defaultClient)) as? String
                let query = selection?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !query.isEmpty, let url = engine.searchURL(for: query) {
                    self.store?.openTab(url, after: self)
                } else if let search, let action = search.action {
                    NSApp.sendAction(action, to: search.target, from: search)
                }
            }
        }
        menu.insertItem(own, at: menu.index(of: search))
        search.isHidden = true
    }
}

extension BrowserStore {
    func open(_ url: URL, at destination: LinkDestination, from tab: BrowserTab) {
        switch destination {
        case .split:
            addToSplit(openTab(url, after: tab, select: false))
        case .newWindow:
            moveToNewWindow(openTab(url, after: tab, select: false))
        case .privateWindow:
            app.openPrivateWindow().openTab(url)
        }
    }
}
