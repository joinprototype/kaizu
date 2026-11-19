#if DEBUG
import AppKit
import BrowserCore

extension DebugHooks {
    @MainActor static func checkSplitCapacity(_ store: BrowserStore) {
        precondition(ProcessInfo.processInfo.environment["KAIZU_SUPPORT"] != nil)
        let space = store.activeSpace
        func require(_ condition: Bool, _ message: String) {
            if !condition { FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1) }
        }
        let tabs = (1...5).map { number in
            store.openTab(URL(string: "about:blank#pane-\(number)")!, select: number == 1)
        }
        store.split(tabs[0], with: tabs[1].id, at: .pane(tabs[0].id, .right))
        store.split(tabs[1], with: tabs[2].id, at: .pane(tabs[1].id, .bottom))
        store.split(tabs[0], with: tabs[3].id, at: .pane(tabs[0].id, .bottom))
        let layout = space.splitLayout
        let selected = store.selectedTab
        require(space.splitTabs.count == 4 && selected === tabs[3], "Expected a full mixed split")
        guard let menuItem = NSApp.mainMenu?.item(withTitle: "View")?.submenu?
            .item(withTitle: "Split with Recent Tab") as? CommandMenuItem else { require(false, "Missing View menu command"); return }
        require(!menuItem.validateMenuItem(menuItem) && !store.paletteCommands.contains { $0.id == "tab.split" },
                "Full split still offers the recent-tab action")
        store.splitWithRecentTab()
        require(store.selectedTab === selected && space.splitLayout == layout, "Recent-tab command switched away from the full split")
        store.addToSplit(tabs[4])
        require(store.selectedTab === selected && space.splitLayout == layout, "Adding a fifth tab switched away from the full split")
        let count = space.today.count
        store.open(URL(string: "about:blank#extra")!, at: .split, from: tabs[0])
        require(space.today.count == count, "Stale link action created an unused fifth tab")
        let other = store.app.addWindow(WindowRecord(activeSpaceID: space.id))
        other.select(tabs[4], in: space)
        other.splitWithRecentTab()
        require(other.selectedTab === tabs[4] && !other.canAddSplitPane && space.splitLayout == layout,
                "Another window could replace the four-pane split")
        store.app.windowDidClose(other)
        store.select(tabs[4])
        require(menuItem.validateMenuItem(menuItem), "The standalone tab did not enable the View menu action")
        require(store.paletteCommands.contains { $0.id == "tab.split" }, "Standalone tab did not offer the palette command")
        NSApp.sendAction(menuItem.action!, to: menuItem.target, from: menuItem)
        require(space.splitTabs == [tabs[4], tabs[3]], "A single tab could not start a fresh split with a recent pane")
        store.closeSplit()
        store.move(tabs[4], to: .favorites(before: nil))
        store.split(tabs[4], with: tabs[3].id, at: .pane(tabs[4].id, .bottom))
        require(store.selectedTab === tabs[3] && space.splitTabs.count == 2, "Expected a focused Today pane beside a favorite")
        store.close(tabs[3])
        require(store.selectedTab === tabs[4] && space.splitLayout == nil, "Closing the selected pane hid the surviving favorite")
        print("Full split kept its four panes and selection; a standalone tab started a new split.")
        NSApp.terminate(nil)
    }
}
#endif
