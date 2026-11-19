import AppKit
import DesignSystem
import SwiftUI

/// "Hide Distracting Items" (see HiddenItems): pick parts of the page in
/// front to hide them on that site from now on.
extension BrowserStore {
    func beginHidingItems(on tab: BrowserTab, for purpose: HiddenItems.Purpose = .hide) {
        guard tab === selectedTab, !tab.profile.isPrivate, tab.url?.host() != nil else { return }
        // A page you'd be told about has to be one Kaizu can open for you.
        if purpose == .watch, tab.url?.scheme != "https" {
            return showToast("Only secure (https) pages can be watched", symbol: "eye.slash")
        }
        endHidingItems()
        withAnimation(Motion.snap) {
            pickingPurpose = purpose
            hidingItemsTabID = tab.id
        }
        HiddenItems.startPicking(in: tab.webView, for: purpose)
        focusWebView()
    }

    /// One part per pick: watching starts and the picker goes away.
    func watchPicked(_ selector: String, text: String, on tab: BrowserTab) {
        guard let url = tab.url else { return }
        let watches = app.watches
        guard let part = watches.add(url: url, selector: selector, text: text, title: tab.displayTitle, profileID: tab.profile.id) else {
            let full = watches.parts.count >= PageWatches.maximum
            return showToast(full ? "Kaizu watches up to \(PageWatches.maximum) parts of pages" : "That part has no text to watch", symbol: "eye.slash")
        }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            endHidingItems()
        }
        showToast("Watching “\(part.text)”. Kaizu checks every hour.", symbol: "eye", undo: { watches.remove(part.id) }, lasts: .seconds(6))
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
