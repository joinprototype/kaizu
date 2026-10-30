import AppKit
import SwiftUI

/// ⌃Tab switcher: hold Control and tap Tab to cycle through the space's
/// tabs in most-recently-used order; releasing Control switches.
struct TabSwitcherState: Equatable {
    var tabIDs: [UUID]
    var index: Int
}

extension BrowserStore {
    static let switcherLimit = 8

    func installTabSwitcherMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if event.type == .keyDown, event.keyCode == 48, event.modifierFlags.contains(.control) {  // Tab
                self.advanceTabSwitcher(backwards: event.modifierFlags.contains(.shift))
                return nil
            }
            guard self.tabSwitcher != nil else { return event }
            if event.type == .keyDown, event.keyCode == 53 {  // Esc
                withAnimation(Motion.snap) { self.tabSwitcher = nil }
                return nil
            }
            if event.type == .flagsChanged, !event.modifierFlags.contains(.control) {
                self.commitTabSwitcher()
            }
            return event
        }
    }

    func advanceTabSwitcher(backwards: Bool) {
        if var state = tabSwitcher {
            state.index = (state.index + (backwards ? -1 : 1) + state.tabIDs.count) % state.tabIDs.count
            withAnimation(Motion.snap) { tabSwitcher = state }
            return
        }
        let current = selectedTab
        let others = activeSpace.allTabs
            .filter { $0 !== current }
            .sorted { ($0.lastActiveAt ?? .distantPast) > ($1.lastActiveAt ?? .distantPast) }
        let tabs = (current.map { [$0] } ?? []) + others
        guard tabs.count > 1 else { return }
        current?.captureThumbnail()
        let ids = tabs.prefix(Self.switcherLimit).map(\.id)
        withAnimation(Motion.pop) {
            tabSwitcher = TabSwitcherState(tabIDs: ids, index: backwards ? ids.count - 1 : 1)
        }
    }

    func commitTabSwitcher(to index: Int? = nil) {
        guard let state = tabSwitcher else { return }
        withAnimation(Motion.snap) { tabSwitcher = nil }
        let id = state.tabIDs[index ?? state.index]
        if let tab = activeSpace.allTabs.first(where: { $0.id == id }), tab !== selectedTab {
            select(tab)
        }
    }

    // MARK: - Now playing

    /// Media state is event-driven (see `MediaEvents`). This only re-checks
    /// tabs already marked as playing, every 10 s, for players that stop
    /// without a DOM event (detached `Audio` objects, Web Audio).
    func startMediaMonitoring() {
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(10))
                guard let self else { return }
                for tab in self.spaces.flatMap(\.allTabs) where tab.isPlayingMedia {
                    await tab.refreshMediaState()
                }
            }
        }
    }

    /// A playing tab other than the one in front, for the sidebar's mini player.
    var backgroundMediaTab: BrowserTab? {
        activeSpace.allTabs.first { $0.isPlayingMedia && $0 !== selectedTab }
    }
}
