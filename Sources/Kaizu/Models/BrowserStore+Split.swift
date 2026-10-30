import AppKit
import SwiftUI

/// Split view: up to four of a space's tabs side by side. The split belongs
/// to the space and shows whenever one of its tabs is selected.
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
        let space = activeSpace
        let current = space.selectedTab
        if space.splitTabs.isEmpty || current.map({ !space.splitTabs.contains($0) }) == true {
            guard let current, current !== tab else { return }
            space.split = [current.id, tab.id]
        } else if !space.split.contains(tab.id), space.splitTabs.count < Self.maxSplitPanes {
            space.split.append(tab.id)
        }
        withAnimation(Motion.glide) {
            select(tab, in: space)
        }
    }

    /// ⌃⇧=: splits the current tab with the one used most recently before it.
    func splitWithRecentTab() {
        guard let current = selectedTab else { return }
        let recent = activeSpace.allTabs
            .filter { $0 !== current && !isInSplit($0) }
            .max { ($0.lastActiveAt ?? .distantPast) < ($1.lastActiveAt ?? .distantPast) }
        if let recent {
            addToSplit(recent)
        }
    }

    /// Whether the sidebar tab `id` can be dropped on `target`'s page.
    func canSplit(_ target: BrowserTab, with id: UUID) -> Bool {
        guard id != target.id, let tab = tab(TabDrag(id: id)) else { return false }
        let panes = activeSpace.splitTabs
        guard panes.contains(target) else { return true }
        return panes.contains(tab) || panes.count < Self.maxSplitPanes
    }

    /// A sidebar tab dropped on one half of `target`'s page: starts a split
    /// with it on that side, or adds it to (or moves it within) the split
    /// `target` is in.
    func split(_ target: BrowserTab, with id: UUID, on edge: HorizontalEdge) {
        guard canSplit(target, with: id), let tab = tab(TabDrag(id: id)) else { return }
        let space = activeSpace
        var panes = space.splitTabs.contains(target) ? space.splitTabs.map(\.id) : [target.id]
        panes.removeAll { $0 == id }
        guard let index = panes.firstIndex(of: target.id) else { return }
        panes.insert(id, at: edge == .leading ? index : index + 1)
        withAnimation(Motion.glide) {
            space.split = panes
            select(tab, in: space)
        }
        scheduleSave()
    }

    /// Drop handling for `tab`'s page in the main window.
    func splitDrop(onto tab: BrowserTab) -> SplitDrop {
        SplitDrop { [weak self] id in
            self?.canSplit(tab, with: id) ?? false
        } perform: { [weak self] id, edge in
            self?.split(tab, with: id, on: edge)
        }
    }

    func removeFromSplit(_ tab: BrowserTab) {
        let space = activeSpace
        withAnimation(Motion.glide) {
            space.split.removeAll { $0 == tab.id }
            if space.splitTabs.isEmpty {
                space.split = []
            }
        }
        scheduleSave()
    }

    func closeSplit() {
        withAnimation(Motion.glide) {
            activeSpace.split = []
        }
        scheduleSave()
    }

    /// Clicking into a pane focuses its tab. Web views swallow mouse events,
    /// so watch them on their way in rather than with a SwiftUI gesture.
    func installSplitFocusMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            let panes = self.activeSpace.splitTabs
            guard panes.count > 1, let window = event.window else { return event }
            let clicked = panes.first { pane in
                guard pane.isLoaded, pane.webView.window === window else { return false }
                return pane.webView.bounds.contains(pane.webView.convert(event.locationInWindow, from: nil))
            }
            if let clicked, clicked !== self.selectedTab {
                self.select(clicked)
            }
            return event
        }
    }
}
