import BrowserCore
import Foundation

/// Session save/restore (`~/Library/Application Support/Kaizu/session.json`).
extension BrowserStore {
    private static var sessionURL: URL {
        AppPaths.support.appending(path: "session.json")
    }

    /// Saves within a second of the first change. Throttled rather than
    /// debounced, so a page that retitles itself every second (unread
    /// counters, timers) can't keep postponing the save.
    func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.saveTask = nil
            self?.save()
        }
    }

    func save() {
        let record = SessionRecord(
            activeSpaceID: activeSpaceID,
            isSidebarVisible: isSidebarVisible,
            sidebarWidth: sidebarWidth,
            profiles: profiles.map(\.record),
            spaces: spaces.map(\.record)
        )
        do {
            try record.encoded().write(to: Self.sessionURL, options: .atomic)
        } catch {
            Log.session.error("Couldn't save the session: \(error.localizedDescription, privacy: .public)")
        }
        updateSpotlight()
    }

    func restore() {
        if let (session, migrated) = loadSession() {
            apply(session)
            if migrated {
                scheduleSave()  // write the upgraded format right away
            }
        }
        if spaces.isEmpty {
            createDefaultSpace()
        }
        if !spaces.contains(where: { $0.id == activeSpaceID }) {
            activeSpaceID = spaces[0].id
        }
        loadArchive()
        selectedTab?.activate()
    }

    func makeTab(_ record: TabRecord, profile: Profile) -> BrowserTab {
        let tab = BrowserTab(
            id: record.id, profile: profile, store: self, url: record.url, title: record.title,
            pinnedURL: record.pinnedURL, lastActiveAt: record.lastActiveAt
        )
        tab.savedState = savedTabState(for: record.id)
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

    private func loadSession() -> (record: SessionRecord, migrated: Bool)? {
        guard let data = try? Data(contentsOf: Self.sessionURL) else { return nil }
        do {
            let (record, sourceVersion) = try SessionRecord.decode(data)
            if sourceVersion < SessionRecord.currentVersion {
                Log.session.notice("Upgrading the session from version \(sourceVersion) to \(SessionRecord.currentVersion)")
                // Keep the pre-migration file, just in case.
                try? data.write(to: AppPaths.support.appending(path: "session.v\(sourceVersion).backup.json"))
            }
            return (record, sourceVersion < SessionRecord.currentVersion)
        } catch {
            Log.session.fault("Couldn't read the session, starting fresh (kept as session.unreadable.json): \(error.localizedDescription, privacy: .public)")
            // Never overwrite a file we couldn't read without keeping a copy.
            try? data.write(to: AppPaths.support.appending(path: "session.unreadable.json"))
            return nil
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
            space.selectedTabID = record.selectedTabID
            space.split = record.split ?? []
            space.splitWidths = record.splitWidths ?? []
            space.appearance = record.appearance.flatMap(Space.Appearance.init) ?? .auto
            return space
        }
        activeSpaceID = session.activeSpaceID ?? activeSpaceID
        isSidebarVisible = session.isSidebarVisible
        sidebarWidth = session.sidebarWidth
    }

    private func createDefaultSpace() {
        let profile = Profile(name: "Personal")
        let space = Space(profile: profile, name: "Personal", symbol: Space.symbols[0], hue: Theme.all[0].hue)
        profiles.append(profile)
        spaces.append(space)
        activeSpaceID = space.id
    }
}
