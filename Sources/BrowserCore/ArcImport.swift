import Foundation

/// What bringing in an Arc sidebar adds to a session. Only ever adds: a space
/// with the same name is added to, anything else becomes a new space, and
/// what's already there stays, so importing twice brings nothing new. The one
/// exception is a fresh install's lone empty space, which becomes the first
/// Arc space instead of sitting empty in front of it.
public struct ArcImport: Equatable, Sendable {
    public struct SpaceSummary: Equatable, Sendable {
        public var name: String
        public var isNew: Bool
        public var pinned: Int
        public var today: Int
    }

    public struct Takeover: Equatable, Sendable {
        public var spaceID: UUID
        public var name: String
        public var hue: Double?
    }

    public var newProfiles: [ProfileRecord] = []
    public var newSpaces: [SpaceRecord] = []
    /// What goes into profiles and spaces that already exist, by id.
    public var favorites: [UUID: [TabRecord]] = [:]
    public var pinned: [UUID: [SidebarItemRecord]] = [:]
    /// New children to append to folders that already exist, keyed by folder ID.
    public var folderAdditions: [UUID: [SidebarItemRecord]] = [:]
    public var today: [UUID: [TabRecord]] = [:]
    public var takeover: Takeover?
    /// One row per Arc space, for the preview.
    public var summary: [SpaceSummary] = []

    /// Every tab that would come across, favorites included.
    public var tabCount: Int {
        let inNewSpaces = newSpaces.reduce(0) { $0 + $1.pinned.tabCount + $1.today.count }
        let inNewProfiles = newProfiles.reduce(0) { $0 + $1.favorites.count }
        let added = pinned.values.reduce(0) { $0 + $1.tabCount } + today.values.reduce(0) { $0 + $1.count }
        let inFolders = folderAdditions.values.reduce(0) { $0 + $1.tabCount }
        return inNewSpaces + inNewProfiles + inFolders + added + favorites.values.reduce(0) { $0 + $1.count }
    }

    /// `hues` and `symbols` are what new spaces cycle through, as they do
    /// when made by hand; a space keeps Arc's color when it has one.
    public init(
        _ sidebar: ArcSidebar, profiles: [ProfileRecord], spaces: [SpaceRecord],
        includesToday: Bool, hues: [Double], symbols: [String], now: Date = Date()
    ) {
        var kaizuProfile: [String: UUID] = [:]
        // Match the default profile first, even if a custom Arc space appears
        // first in the file. Custom profiles must never claim its destination.
        let defaultSpaces = sidebar.spaces.filter { $0.profile == ArcSidebar.defaultProfile }
        if !defaultSpaces.isEmpty {
            let existing = defaultSpaces.lazy.compactMap { arc in
                spaces.first { $0.name.caseInsensitiveCompare(arc.name) == .orderedSame }
            }.first
            kaizuProfile[ArcSidebar.defaultProfile] = (existing ?? spaces.first)?.profileID
        }
        var matches: [Int: SpaceRecord] = [:]
        var taken: Set<UUID> = []
        for (index, arc) in sidebar.spaces.enumerated() {
            let match = spaces.first { space in
                guard !taken.contains(space.id), space.name.caseInsensitiveCompare(arc.name) == .orderedSame else { return false }
                if let destination = kaizuProfile[arc.profile] { return destination == space.profileID }
                return !kaizuProfile.values.contains(space.profileID)
            }
            guard let match else { continue }
            matches[index] = match
            taken.insert(match.id)
            kaizuProfile[arc.profile] = match.profileID
        }
        if matches.isEmpty, spaces.count == 1, let only = spaces.first, only.pinned.isEmpty, only.today.isEmpty,
           let index = sidebar.spaces.firstIndex(where: { $0.profile == ArcSidebar.defaultProfile }) {
            let arc = sidebar.spaces[index]
            matches[index] = only
            takeover = Takeover(spaceID: only.id, name: arc.name, hue: arc.hue)
        }
        var spaceCount = spaces.count
        for (index, arc) in sidebar.spaces.enumerated() {
            let today = includesToday ? arc.today : []
            if let match = matches[index] {
                let favorites = profiles.first { $0.id == match.profileID }?.favorites ?? []
                let known = Self.addresses(of: match.pinned.tabs + match.today + favorites)
                var folders: [UUID: [SidebarItemRecord]] = [:]
                let pinned = Self.additions(arc.pinned, alongside: match.pinned, skipping: known, folders: &folders)
                for (id, items) in folders { folderAdditions[id] = items }
                let pinnedCount = folders.values.reduce(pinned.tabCount) { $0 + $1.tabCount }
                let fresh = today.filter { !known.contains($0.url) }.map { Self.record($0, now: now) }
                if !pinned.isEmpty { self.pinned[match.id] = pinned }
                if !fresh.isEmpty { self.today[match.id] = fresh }
                summary.append(SpaceSummary(name: arc.name, isNew: false, pinned: pinnedCount, today: fresh.count))
                continue
            }
            let profileID = kaizuProfile[arc.profile] ?? UUID()
            if kaizuProfile[arc.profile] == nil {
                kaizuProfile[arc.profile] = profileID
                newProfiles.append(ProfileRecord(id: profileID, name: arc.name, favorites: []))
            }
            let pinned = arc.pinned.compactMap { Self.record($0, skipping: []) }
            newSpaces.append(SpaceRecord(
                id: UUID(), name: arc.name, symbol: symbols[spaceCount % symbols.count],
                hue: arc.hue ?? hues[spaceCount % hues.count], profileID: profileID, selectedTabID: nil,
                pinned: pinned, today: today.map { Self.record($0, now: now) }
            ))
            spaceCount += 1
            summary.append(SpaceSummary(name: arc.name, isNew: true, pinned: pinned.tabCount, today: today.count))
        }

        // Favorites of an Arc profile with no space here have nowhere to go.
        for (profile, tabs) in sidebar.favorites {
            guard let id = kaizuProfile[profile] else { continue }
            if let index = newProfiles.firstIndex(where: { $0.id == id }) {
                newProfiles[index].favorites = tabs.map { Self.pinnedRecord($0) }
            } else {
                let known = Self.addresses(of: profiles.first { $0.id == id }?.favorites ?? [])
                let fresh = tabs.filter { !known.contains($0.url) }.map { Self.pinnedRecord($0) }
                if !fresh.isEmpty { favorites[id] = fresh }
            }
        }
    }

    private static func addresses(of tabs: [TabRecord]) -> Set<URL> {
        Set(tabs.flatMap { [$0.url, $0.pinnedURL].compactMap(\.self) })
    }

    /// Reuse a folder only when its name identifies one sibling on each side.
    /// Absolute paths and sidebar order can change, and Arc exports allow repeated headings.
    private static func additions(
        _ source: [ArcSidebar.Item], alongside existing: [SidebarItemRecord], skipping known: Set<URL>,
        folders: inout [UUID: [SidebarItemRecord]]
    ) -> [SidebarItemRecord] {
        var byName: [String: FolderRecord] = [:]
        var ambiguous = Set<String>()
        for case .folder(let folder) in existing {
            if byName.updateValue(folder, forKey: folder.name) != nil { ambiguous.insert(folder.name) }
        }
        var seen = Set<String>()
        for case .folder(let name, _) in source where !seen.insert(name).inserted {
            ambiguous.insert(name)
        }
        return source.compactMap { item in
            guard case .folder(let name, let children) = item, let folder = byName[name], !ambiguous.contains(name) else {
                return record(item, skipping: known)
            }
            let added = additions(children, alongside: folder.children, skipping: known, folders: &folders)
            if !added.isEmpty { folders[folder.id] = added }
            return nil
        }
    }

    private static func record(_ item: ArcSidebar.Item, skipping known: Set<URL>) -> SidebarItemRecord? {
        switch item {
        case .tab(let tab):
            return known.contains(tab.url) ? nil : .tab(pinnedRecord(tab))
        case .folder(let name, let children):
            let kept = children.compactMap { record($0, skipping: known) }
            return kept.isEmpty ? nil : .folder(FolderRecord(id: UUID(), name: name, isExpanded: true, children: kept))
        }
    }

    private static func pinnedRecord(_ tab: ArcSidebar.Tab) -> TabRecord {
        TabRecord(id: UUID(), title: tab.title, url: tab.url, pinnedURL: tab.url, customTitle: tab.customTitle)
    }

    /// Stamped now, so the clock on archiving starts from the import.
    private static func record(_ tab: ArcSidebar.Tab, now: Date) -> TabRecord {
        TabRecord(id: UUID(), title: tab.title, url: tab.url, lastActiveAt: now, customTitle: tab.customTitle)
    }
}

extension [SidebarItemRecord] {
    /// All tabs, depth-first in sidebar order.
    var tabs: [TabRecord] {
        flatMap { item -> [TabRecord] in
            switch item {
            case .tab(let tab): [tab]
            case .folder(let folder): folder.children.tabs
            }
        }
    }

    var tabCount: Int { tabs.count }
}

extension ArcImport {
    /// The sidebar identities owned by this import, including folders and profile favorites.
    public var addedItemIDs: Set<UUID> {
        var ids = Set<UUID>()
        func include(_ items: [SidebarItemRecord]) {
            for item in items {
                switch item {
                case .tab(let tab): ids.insert(tab.id)
                case .folder(let folder):
                    ids.insert(folder.id)
                    include(folder.children)
                }
            }
        }
        for items in pinned.values { include(items) }
        for items in folderAdditions.values { include(items) }
        for space in newSpaces {
            include(space.pinned)
            ids.formUnion(space.today.map(\.id))
        }
        for tabs in today.values { ids.formUnion(tabs.map(\.id)) }
        for tabs in favorites.values { ids.formUnion(tabs.map(\.id)) }
        for profile in newProfiles { ids.formUnion(profile.favorites.map(\.id)) }
        return ids
    }
}
