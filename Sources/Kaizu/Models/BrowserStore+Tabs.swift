import AppKit
import BrowserCore
import DesignSystem
import SwiftUI
import WebKit

extension BrowserStore {
    // MARK: - Opening and selecting

    /// Opens a tab in Today: right after `opener` when it's a today tab, else at the top.
    @discardableResult
    func openTab(
        _ url: URL?,
        in space: Space? = nil,
        after opener: BrowserTab? = nil,
        select: Bool = true,
        configuration: WKWebViewConfiguration? = nil
    ) -> BrowserTab {
        // A tab opened from a little window or a peek isn't in a space: it
        // goes to one on the opener's profile, so it keeps its cookies.
        let space = space ?? opener.flatMap { self.space(containing: $0) ?? self.space(on: $0.profile) } ?? activeSpace
        let tab = BrowserTab(profile: space.profile, app: app, url: url, configuration: configuration)
        insertToday(tab, in: space, after: opener, select: select)
        return tab
    }

    private func insertToday(_ tab: BrowserTab, in space: Space, after opener: BrowserTab? = nil, select: Bool = true) {
        withAnimation(Motion.pop) {
            if let opener, let index = space.today.firstIndex(of: opener) {
                space.today.insert(tab, at: index + 1)
            } else {
                space.today.insert(tab, at: 0)
            }
        }
        extensions.didOpen(tab)
        if select {
            self.select(tab, in: space)
        }
        scheduleSave()
    }

    /// A page can only be in one window: selecting a tab that's showing in
    /// another brings that window forward instead.
    func select(_ tab: BrowserTab, in space: Space? = nil) {
        let space = space ?? self.space(containing: tab) ?? activeSpace
        if let other = space.panes(with: tab).lazy.compactMap(app.store(showing:)).first(where: { $0 !== self }) {
            other.window?.makeKeyAndOrderFront(nil)
            app.front = other
            return other.show(tab, in: other.space(containing: tab) ?? other.activeSpace)
        }
        show(tab, in: space)
    }

    private func show(_ tab: BrowserTab, in space: Space) {
        let now = Date()
        let previousActiveTab = selectedTab
        let previous = selectedTab(in: space)
        previous?.captureThumbnail()
        if let previous, previous !== tab, previous.isPlayingMedia, settings.autoPictureInPicture,
           !space.splitTabs.contains(previous) {
            previous.enterPictureInPicture()
        }
        // Leaving a tab counts as activity too, or a long-read tab would be
        // archived the moment you switch away from it.
        previous?.lastActiveAt = now
        tab.lastActiveAt = now
        if space.splitTabs.contains(tab) {
            space.splitTabs.forEach { $0.lastActiveAt = now }
        }
        if reader?.tabID != tab.id {
            reader = nil
        }
        if capture != tab.id {
            capture = nil
        }
        if hidingItemsTabID != tab.id {
            endHidingItems()
        }
        activeSpaceID = space.id
        setSelected(tab, in: space)
        tab.activate()
        extensions.didActivate(tab, previous: previousActiveTab)
        if previous !== tab {
            tab.exitPictureInPicture()
            // Catches players that make no DOM events, as they go to the background.
            Task { await previous?.refreshMediaState() }
        }
        focusWebView()
        scheduleSave()
    }

    /// The space whose pinned section or today list holds `tab` (nil for favorites).
    func space(containing tab: BrowserTab) -> Space? {
        spaces.first { $0.today.contains(tab) || $0.pinned.tabs.contains(tab) }
    }

    /// The active space if it's on `profile`, else the first one that is.
    func space(on profile: Profile) -> Space? {
        activeSpace.profile === profile ? activeSpace : spaces.first { $0.profile === profile }
    }

    func selectTab(number: Int) {
        let tabs = activeSpace.visibleTabs
        guard !tabs.isEmpty else { return }
        let index = number == 9 ? tabs.count - 1 : number - 1
        if tabs.indices.contains(index) {
            select(tabs[index])
        }
    }

    func selectAdjacentTab(_ offset: Int) {
        let elsewhere = tabsElsewhere
        let tabs = activeSpace.visibleTabs.filter { !elsewhere.contains($0) }
        guard !tabs.isEmpty else { return }
        guard let current = tabs.firstIndex(where: { $0.id == selectedTabIDs[activeSpace.id] }) else {
            return select(tabs[0])
        }
        select(tabs[(current + offset + tabs.count) % tabs.count])
    }

    /// Resolves a tab dragged from the sidebar.
    func tab(_ drag: TabDrag) -> BrowserTab? {
        activeSpace.tab(id: drag.id)
    }

    // MARK: - Closing

    /// ⌘W, a row's close button or its menu. A page's `window.close()` and
    /// extensions use `close` and stay silent, since they can repeat it.
    func userClose(_ tab: BrowserTab) {
        sounds.play(.closeTab)
        close(tab)
    }

    /// Today tabs close for good (⇧⌘T brings them back); favorites and pinned
    /// tabs stay and reset to their saved address, like Arc.
    func close(_ tab: BrowserTab) {
        if let littleWindow = app.littleWindows.first(where: { $0.tab === tab }) {
            return littleWindow.close()
        }
        let space = space(containing: tab) ?? activeSpace
        let showing = app.allStores.filter { $0.selectedTabIDs[space.id] == tab.id }
        for store in app.allStores where store.hidingItemsTabID == tab.id {
            store.endHidingItems()
        }
        let previousSplit = space.split
        var neighborIndex = 0
        space.removeFromSplit(tab.id)
        if let index = space.today.firstIndex(of: tab) {
            closedTabs.remember(tab, in: space.id)
            withAnimation(Motion.snap) {
                _ = space.today.remove(at: index)
            }
            tab.discard()
            extensions.didClose(tab)
            neighborIndex = index
        } else {
            tab.unload()
        }
        for store in showing {
            store.selectNeighbor(of: neighborIndex, in: space, previousSplit: previousSplit)
        }
        scheduleSave()
    }

    /// Prefer a remaining pane of the visible split, then a nearby Today tab.
    /// In an inactive space, only update the remembered selection.
    func selectNeighbor(of index: Int, in space: Space, excluding tab: BrowserTab? = nil, previousSplit: [UUID] = []) {
        // A tab that's going somewhere isn't going to the background, so
        // it's no one's "previous" page, to float in picture in picture.
        if tab != nil {
            setSelected(nil, in: space)
        }
        let elsewhere = tabsElsewhere
        let free = space.today.enumerated().filter { $0.element !== tab && !elsewhere.contains($0.element) }
        var next = (free.first { $0.offset >= index } ?? free.last)?.element
        if let selected = selectedTabIDs[space.id], let pane = previousSplit.firstIndex(of: selected) {
            let neighbors = Array(previousSplit.dropFirst(pane + 1)) + previousSplit.prefix(pane).reversed()
            if let survivor = neighbors.lazy.compactMap(space.tab(id:)).first(where: { !elsewhere.contains($0) }) {
                next = survivor
            }
        }
        if let next, space.id == activeSpaceID {
            select(next, in: space)
        } else {
            setSelected(next, in: space)
        }
    }

    /// The tab's page goes to a window of its own; this space's sidebars
    /// keep listing it.
    func moveToNewWindow(_ tab: BrowserTab) {
        let space = space(containing: tab) ?? activeSpace
        if isInSplit(tab) {
            removeFromSplit(tab)
        }
        let store = app.openWindow(on: space)
        store.takeOver(tab)
        store.select(tab, in: space)
    }

    /// Any other window showing `tab` moves on, so this one can have its page.
    func takeOver(_ tab: BrowserTab) {
        for store in app.stores where store !== self && store.isShowing(tab) {
            let space = store.activeSpace
            store.selectNeighbor(of: space.today.firstIndex(of: tab) ?? 0, in: space, excluding: tab)
        }
    }

    func closeSelectedTab() {
        if let littleWindow = app.keyLittleWindow {
            littleWindow.close()
        } else if let keyWindow = NSApp.keyWindow, keyWindow !== window {
            // Settings, History: ⌘W closes that window, not a tab behind it.
            keyWindow.performClose(nil)
        } else if peek != nil {
            closePeek()
        } else if let selectedTab {
            userClose(selectedTab)
        } else {
            window?.performClose(nil)
        }
    }

    /// Arc's "Clear": closes every today tab in the space (undoable from the toast).
    func clearToday(in space: Space) {
        let cleared = space.today
        guard !cleared.isEmpty else { return }
        let ids = Set(cleared.map(\.id))
        let previousLayout = space.splitLayout
        for (index, tab) in cleared.enumerated() {
            closedTabs.remember(tab, in: space.id, keepsHistory: index >= cleared.count - ClosedTab.historyCount)
            extensions.didClose(tab)
            tab.markNotificationsRead()
        }
        withAnimation(Motion.snap, completionCriteria: .removed) {
            space.today = []
            space.splitLayout = space.survivingSplit(previousLayout)
        } completion: {
            // After the rows have gone, so tearing pages down can't drop
            // frames; hibernating keeps their state in case of Undo.
            for tab in cleared where !space.today.contains(tab) {
                tab.hibernate()
            }
        }
        let remainingLayout = space.splitLayout
        for store in app.allStores where store.selectedTabIDs[space.id].map(ids.contains) == true {
            store.selectNeighbor(of: 0, in: space, previousSplit: previousLayout?.panes ?? [])
        }
        scheduleSave()
        showToast("Closed \(cleared.count.counted("tab"))", symbol: "xmark.circle") { [weak self] in
            guard let self, spaces.contains(where: { $0 === space }) else { return }
            // A tab reopened with ⇧⌘T is already back, possibly in another space.
            let stillClosed = Set(closedTabs.lazy.map(\.record.id).filter(ids.contains))
            let restoring = cleared.filter { stillClosed.contains($0.id) }
            withAnimation(Motion.pop) {
                space.today = restoring + space.today
                if remainingLayout != previousLayout, space.splitLayout == remainingLayout {
                    space.splitLayout = space.survivingSplit(previousLayout)
                }
            }
            restoring.forEach { extensions.didOpen($0) }
            closedTabs.removeAll { ids.contains($0.record.id) }
            scheduleSave()
        }
    }

    func reopenClosedTab() {
        while let closed = closedTabs.popLast() {
            // If its space was deleted, another space on the same profile keeps its cookies.
            let space = spaces.first { $0.id == closed.spaceID && $0.profile.id == closed.profileID }
                ?? spaces.first { $0.profile.id == closed.profileID }
            guard let space else { continue }
            reopen(closed.record, in: space, navigationState: closed.navigationState)
            sounds.play(.openTab)
            return
        }
    }

    func reopen(_ record: TabRecord, in space: Space, id: UUID = UUID(), navigationState: Data? = nil) {
        let tab = BrowserTab(reopening: record, id: id, profile: space.profile, app: app, navigationState: navigationState)
        insertToday(tab, in: space)
    }

    // MARK: - Moving

    func move(_ tab: BrowserTab, to destination: TabDestination, in space: Space? = nil) {
        // Dropped on its own row: it's already there.
        guard destination.before != tab.id else { return }
        let space = space ?? activeSpace
        let wasPinned = tab.pinnedURL != nil
        // The same curve as the gap that opened for it.
        withAnimation(Motion.glide) {
            detach(tab)
            switch destination {
            case .favorites(let before):
                tab.pinnedURL = tab.pinnedURL ?? tab.url
                tab.profile.favorites.insert(tab, before: before)
            case .pinned(let folder, let before):
                tab.pinnedURL = tab.pinnedURL ?? tab.url
                if let folder {
                    folder.children.insert(.tab(tab), before: before)
                } else {
                    space.pinned.insert(.tab(tab), before: before)
                }
            case .today(let before):
                tab.pinnedURL = nil
                space.today.insert(tab, before: before)
            }
        }
        // Only for a change of state: reordering is the rows' own business.
        if wasPinned != (tab.pinnedURL != nil) {
            sounds.play(wasPinned ? .unpin : .pin)
        }
        scheduleSave()
    }

    /// To `target`'s Today. A page can't change profile, so across profiles
    /// it reopens there, with that profile's logins. Windows showing it move on.
    func move(_ tab: BrowserTab, toSpace target: Space) {
        guard let source = space(containing: tab), source !== target else { return }
        let index = source.today.firstIndex(of: tab) ?? 0
        for store in app.stores where store.selectedTabIDs[source.id] == tab.id {
            store.selectNeighbor(of: index, in: source, excluding: tab)
        }
        source.removeFromSplit(tab.id)
        if tab.profile === target.profile {
            move(tab, to: .today(before: target.today.first?.id), in: target)
        } else {
            detach(tab)
            let reopened = openTab(tab.pinnedURL ?? tab.url, in: target, select: false)
            reopened.title = tab.title
            reopened.customTitle = tab.customTitle
            app.discard([tab])
        }
        showToast("Moved to \(target.name)", symbol: target.symbol)
        scheduleSave()
    }

    /// ⌘D: pin a today tab, or send a favorite/pinned tab back to Today,
    /// with a small toast that can undo it.
    func togglePin(_ tab: BrowserTab) {
        guard !isPrivate else { return }
        let space = activeSpace
        guard let original = place(of: tab) else { return }
        let pinnedURL = tab.pinnedURL
        // Puts it back exactly: same space (even after switching), same
        // pinned page; skipped if the tab or its folder is gone by then.
        let undo: @MainActor () -> Void = { [weak self] in
            guard let self, self.spaces.contains(where: { $0 === space }), self.place(of: tab) != nil else { return }
            if case .pinned(let folder?, _) = original, !space.pinned.folders.contains(where: { $0 === folder }) { return }
            self.move(tab, to: original, in: space)
            tab.pinnedURL = pinnedURL
        }
        if space.today.contains(tab) {
            move(tab, to: .pinned(folder: nil, before: nil))
            showToast("Pinned to \(space.name)", symbol: "pin.fill", undo: undo)
        } else {
            move(tab, to: .today(before: space.today.first?.id))
            showToast("Moved to Today", symbol: "pin.slash", undo: undo)
        }
    }

    /// Where `tab` sits now, as a destination that would put it back there.
    func place(of tab: BrowserTab) -> TabDestination? {
        func next<T: Identifiable>(after index: Int, in items: [T]) -> T.ID? {
            items.indices.contains(index + 1) ? items[index + 1].id : nil
        }
        if let index = tab.profile.favorites.firstIndex(of: tab) {
            return .favorites(before: next(after: index, in: tab.profile.favorites))
        }
        for space in spaces {
            if let index = space.today.firstIndex(of: tab) {
                return .today(before: next(after: index, in: space.today))
            }
            let folder = space.pinned.parent(of: tab.id)
            let siblings = folder?.children ?? space.pinned
            if let index = siblings.firstIndex(where: { $0.id == tab.id }) {
                return .pinned(folder: folder, before: next(after: index, in: siblings))
            }
        }
        return nil
    }

    private func detach(_ tab: BrowserTab) {
        tab.profile.favorites.removeAll { $0 === tab }
        for space in spaces {
            space.pinned.remove(id: tab.id)
            space.today.removeAll { $0 === tab }
        }
    }

    // MARK: - Folders

    /// Creates a folder at the top of the pinned section, optionally holding `tab`.
    func newFolder(with tab: BrowserTab? = nil) {
        guard !isPrivate else { return }
        let folder = Folder(name: "New Folder")
        withAnimation(Motion.snap) {
            activeSpace.pinned.insert(.folder(folder), at: 0)
        }
        if let tab {
            move(tab, to: .pinned(folder: folder, before: nil))
        }
        renamingFolderID = folder.id
        scheduleSave()
    }

    /// An empty name goes back to the page's title.
    func rename(_ tab: BrowserTab, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        tab.customTitle = name.isEmpty ? nil : name
        renamingTabID = nil
        scheduleSave()
    }

    func rename(_ folder: Folder, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            folder.name = name
        }
        renamingFolderID = nil
        scheduleSave()
    }

    func toggle(_ folder: Folder) {
        withAnimation(Motion.snap) {
            folder.isExpanded.toggle()
        }
        scheduleSave()
    }

    /// Removes the folder; nothing is lost, its tabs move to the top of Today.
    func delete(_ folder: Folder) {
        let space = activeSpace
        let tabs = folder.children.tabs
        withAnimation(Motion.snap) {
            space.pinned.remove(id: folder.id)
            for tab in tabs.reversed() {
                tab.pinnedURL = nil
                space.today.insert(tab, at: 0)
            }
        }
        scheduleSave()
    }

    // MARK: - Sharing

    /// ⇧⌘2: the visible page to the clipboard, ready to paste.
    func copyLink(of tab: BrowserTab? = nil, asMarkdown: Bool = false) {
        guard let tab = tab ?? selectedTab, let url = tab.url else { return }
        let clean = (TrackingParameters.stripped(url) ?? url).absoluteString
        let title = tab.displayTitle.replacingOccurrences(of: "]", with: "\\]")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(asMarkdown ? "[\(title)](\(clean))" : clean, forType: .string)
        // The address pill confirms inline; with the sidebar hidden, a toast does.
        guard isSidebarVisible else { return showToast("Copied link", symbol: "link") }
        withAnimation(Motion.snap) { didCopyLink = true }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(Motion.snap) { self?.didCopyLink = false }
        }
    }
}
