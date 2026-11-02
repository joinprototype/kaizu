import AppKit
import BrowserCore
import SwiftUI

/// Split view: up to four of a space's tabs, in rows and columns in any mix.
/// The split belongs to the space and shows whenever one of its tabs is selected.
extension BrowserStore {
    static let maxSplitPanes = 4

    func isInSplit(_ tab: BrowserTab) -> Bool {
        // Cheap id check first: sidebar rows ask this on every render.
        activeSpace.split.contains(tab.id) && activeSpace.splitTabs.contains(tab)
    }

    /// Splits `tab` with the selected tab, or adds it to the split on
    /// screen. A split that isn't showing (another tab is selected) gives
    /// way to a new one with the selected tab.
    func addToSplit(_ tab: BrowserTab) {
        guard !isSplitElsewhere else { return showToast("Split View is open in another window", symbol: "rectangle.split.2x1") }
        let space = activeSpace
        let current = selectedTab
        if space.splitTabs.isEmpty || current.map({ !space.splitTabs.contains($0) }) == true {
            guard let current, current !== tab else { return }
            space.splitLayout = .row([current.id, tab.id])
        } else if !space.split.contains(tab.id), space.splitTabs.count < Self.maxSplitPanes {
            space.splitLayout = space.splitLayout?.appending(tab.id)
        }
        takeOver(tab)
        withAnimation(Motion.glide) {
            select(tab, in: space)
        }
    }

    /// A space has one split: while another window shows it, this one leaves it alone.
    private var isSplitElsewhere: Bool {
        let elsewhere = tabsElsewhere
        return activeSpace.splitTabs.contains(where: elsewhere.contains)
    }

    /// ⌃⇧=: splits the current tab with the one used most recently before it.
    func splitWithRecentTab() {
        guard let current = selectedTab else { return }
        let elsewhere = tabsElsewhere
        let recent = activeSpace.allTabs
            .filter { $0 !== current && !isInSplit($0) && !elsewhere.contains($0) }
            .max { ($0.lastActiveAt ?? .distantPast) < ($1.lastActiveAt ?? .distantPast) }
        if let recent {
            addToSplit(recent)
        }
    }

    /// Whether the sidebar tab `id` can be dropped on `target`'s page.
    func canSplit(_ target: BrowserTab, with id: UUID) -> Bool {
        guard id != target.id, !isSplitElsewhere, let tab = tab(TabDrag(id: id)) else { return false }
        let panes = activeSpace.splitTabs
        guard panes.contains(target) else { return true }
        return panes.contains(tab) || panes.count < Self.maxSplitPanes
    }

    /// A sidebar tab dropped on `target`'s page: starts a split with it there,
    /// or adds it to (or moves it within) the split `target` is in. It takes
    /// half of `target`'s pane, whichever way that pane's neighbors run, or
    /// half of the split along its outer edge, which is how a split comes to
    /// mix rows and columns.
    func split(_ target: BrowserTab, with id: UUID, at place: SplitPlace) {
        guard canSplit(target, with: id), let tab = tab(TabDrag(id: id)) else { return }
        let space = activeSpace
        takeOver(tab)
        withAnimation(Motion.glide) {
            space.splitLayout = space.layout(of: space.panes(with: target)).placing(id, at: place)
            select(tab, in: space)
        }
        scheduleSave()
    }

    func removeFromSplit(_ tab: BrowserTab) {
        let space = activeSpace
        withAnimation(Motion.glide) {
            space.removeFromSplit(tab.id)
        }
        scheduleSave()
    }

    func closeSplit() {
        guard !isSplitElsewhere else { return }
        withAnimation(Motion.glide) {
            activeSpace.splitLayout = nil
        }
        scheduleSave()
    }

    /// Clicking into a pane focuses its tab. Web views swallow mouse events,
    /// so watch them on their way in rather than with a SwiftUI gesture.
    func installSplitFocusMonitor() {
        addEventMonitor(matching: .leftMouseDown) { store, event in
            let panes = store.activeSpace.splitTabs
            guard panes.count > 1, let window = event.window else { return event }
            let clicked = panes.first { pane in
                guard pane.isLoaded, pane.webView.window === window else { return false }
                return pane.webView.bounds.contains(pane.webView.convert(event.locationInWindow, from: nil))
            }
            if let clicked, clicked !== store.selectedTab {
                store.select(clicked)
            }
            return event
        }
    }
}
