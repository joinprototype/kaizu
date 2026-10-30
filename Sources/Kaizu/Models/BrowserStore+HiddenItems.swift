import AppKit
import SwiftUI

/// "Hide Distracting Items" (see HiddenItems): pick parts of the page in
/// front to hide them on that site from now on.
extension BrowserStore {
    func beginHidingItems(on tab: BrowserTab) {
        guard tab === selectedTab, !tab.profile.isPrivate, tab.url?.host() != nil else { return }
        endHidingItems()
        withAnimation(Motion.snap) { hidingItemsTabID = tab.id }
        HiddenItems.startPicking(in: tab.webView)
        focusWebView()
    }

    func endHidingItems() {
        guard let id = hidingItemsTabID else { return }
        withAnimation(Motion.snap) { hidingItemsTabID = nil }
        if let tab = spaces.lazy.flatMap(\.allTabs).first(where: { $0.id == id }), tab.isLoaded {
            HiddenItems.stopPicking(in: tab.webView)
        }
    }

    /// Brings back everything hidden on the tab's site.
    func showHiddenItems(on tab: BrowserTab) {
        settings.showHiddenItems(on: tab.url)
        tab.reload()
        showToast("Hidden items are back on \(tab.url?.displayHost ?? "this site")", symbol: "eye")
    }
}
