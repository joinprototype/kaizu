import AppKit
import BrowserCore
import SwiftUI
import WebKit

/// Links from other apps (with Kaizu as the default browser) and the
/// little windows they open in.
extension BrowserStore {
    /// Routes a link opened from another app: an Air Traffic Control rule
    /// picks a space, otherwise the "links open in" setting decides.
    /// Returns whether the main window should come forward.
    @discardableResult
    func openExternal(_ url: URL) -> Bool {
        // Rules for spaces that are gone (deleted before rules were removed
        // with them) don't shadow later ones.
        let routes = settings.linkRoutes.filter { route in spaces.contains { $0.id == route.spaceID } }
        if let route = routes.first(matching: url),
           let space = spaces.first(where: { $0.id == route.spaceID }) {
            // In this window if it's on that space, else in one that is.
            let store = activeSpaceID == space.id ? self : app.stores.first { $0.activeSpaceID == space.id } ?? self
            store.openTab(url, in: space)
            app.front = store
            return true
        }
        switch settings.externalLinks {
        case .littleWindow:
            openLittleWindow(url)
            return false
        case .currentSpace:
            openTab(url)
            return true
        }
    }

    /// `profile` defaults to the active space's; `configuration` is for
    /// popups, which WebKit loads itself.
    @discardableResult
    func openLittleWindow(_ url: URL? = nil, profile: Profile? = nil, configuration: WKWebViewConfiguration? = nil) -> BrowserTab {
        let tab = BrowserTab(profile: profile ?? activeSpace.profile, app: app, url: url, configuration: configuration)
        let controller = LittleWindowController(tab: tab, app: app)
        app.littleWindows.append(controller)
        controller.showWindow(nil)
        tab.activate()
        return tab
    }

    /// A window with its own in-memory profile: no history, nothing saved,
    /// no extensions; everything is gone when it closes.
    func openPrivateWindow() {
        openLittleWindow(profile: Profile(name: "Private", isPrivate: true))
    }

    /// Moves a little window's page into the main window, live (no reload).
    func adopt(_ tab: BrowserTab) {
        let space = spaces.first { $0.profile === tab.profile } ?? activeSpace
        withAnimation(Motion.snap) {
            space.today.insert(tab, at: 0)
        }
        extensions.didOpen(tab)
        select(tab, in: space)
        window?.makeKeyAndOrderFront(nil)
        scheduleSave()
    }

    /// The tab menu commands (reload, back, zoom, copy link…) act on: the key
    /// little window's, or the selected tab while the main window is key.
    /// Nil in Settings or History, so ⌘R there doesn't reach a hidden page.
    var commandTab: BrowserTab? {
        if let littleWindow = app.keyLittleWindow { return littleWindow.tab }
        return window?.isKeyWindow == true ? selectedTab : nil
    }
}
