import BrowserCore
import Foundation

/// Session save/restore (`~/Library/Application Support/Kaizu/session.json`).
extension AppModel {
    private static var sessionURL: URL {
        SessionFiles(directory: AppPaths.support).primary
    }

    /// One write at a time, in order, so a late one can't undo a newer one.
    private static let sessionQueue = DispatchQueue(label: "com.joinprototype.kaizu.session", qos: .utility)

    /// Saves within a second of the first change. Throttled rather than
    /// debounced, so a page that retitles itself every second (unread
    /// counters, timers) can't keep postponing the save.
    func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.saveTask = nil
            self?.save(inBackground: true)
        }
        scheduleSpotlightUpdate()
    }

    /// Pages retitle themselves all the time, so the regular saves leave the
    /// main thread. Quitting writes in place, after any that's still going.
    func save(inBackground: Bool = false) {
        let record = SessionRecord(windows: stores.map(\.record), profiles: profiles.map(\.record), spaces: spaces.map(\.record))
        let url = Self.sessionURL
        let write: @Sendable () -> Void = {
            do {
                try record.encoded().write(to: url, options: .atomic)
            } catch {
                Log.session.error("Couldn't save the session: \(error.localizedDescription, privacy: .public)")
            }
        }
        if inBackground {
            Self.sessionQueue.async(execute: write)
        } else {
            Self.sessionQueue.sync(execute: write)
        }
    }

    func restore(_ session: SessionFiles.Opened?) {
        if let session {
            apply(session.record)
        }
        if spaces.isEmpty {
            createDefaultSpace()
        }
        for record in session?.record.windows ?? [WindowRecord()] {
            addWindow(record)
        }
        if session?.needsSave == true {
            scheduleSave()
        }
        loadArchive()
        stores.forEach { $0.selectedTab?.activate() }
    }

    func makeTab(_ record: TabRecord, profile: Profile) -> BrowserTab {
        let tab = BrowserTab(
            id: record.id, profile: profile, app: self, url: record.url, title: record.title,
            pinnedURL: record.pinnedURL, lastActiveAt: record.lastActiveAt
        )
        tab.savedState = savedTabState(for: record.id)
        tab.customTitle = record.customTitle
        return tab
    }

    func makeItem(_ record: SidebarItemRecord, profile: Profile) -> SidebarItem {
        switch record {
        case .tab(let tab):
            .tab(makeTab(tab, profile: profile))
        case .folder(let folder):
            .folder(Folder(
                id: folder.id, name: folder.name, isExpanded: folder.isExpanded,
                children: folder.children.map { makeItem($0, profile: profile) }
            ))
        }
    }

    private func apply(_ session: SessionRecord) {
        profiles = session.profiles.map { record in
            let profile = Profile(id: record.id, name: record.name)
            profile.favorites = record.favorites.map { makeTab($0, profile: profile) }
            return profile
        }
        spaces = session.spaces.compactMap { record in
            guard let profile = profiles.first(where: { $0.id == record.profileID }) else { return nil }
            let space = Space(id: record.id, profile: profile, name: record.name, symbol: record.symbol, hue: record.hue)
            space.pinned = record.pinned.map { makeItem($0, profile: profile) }
            space.today = record.today.map { makeTab($0, profile: profile) }
            space.splitLayout = SplitNode.restored(layout: record.splitLayout, panes: record.split ?? [], widths: record.splitWidths ?? [])
            space.appearance = record.appearance.flatMap(Space.Appearance.init) ?? .auto
            return space
        }
    }

    private func createDefaultSpace() {
        let profile = Profile(name: "Personal")
        let space = Space(profile: profile, name: "Personal", symbol: Space.symbols[0], hue: Theme.all[0].hue)
        profiles.append(profile)
        spaces.append(space)
    }
}
