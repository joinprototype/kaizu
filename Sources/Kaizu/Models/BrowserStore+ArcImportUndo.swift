import BrowserCore
import Foundation

extension BrowserStore {
    /// Remove exactly the items in this import, even if the user rearranged the sidebar in another window.
    func undoArcImport(_ plan: ArcImport) {
        let ids = plan.addedItemIDs
        for profile in profiles {
            app.discard(profile.favorites.filter { ids.contains($0.id) })
            profile.favorites.removeAll { ids.contains($0.id) }
        }
        for space in spaces {
            let removed = (space.pinned.tabs + space.today).filter { ids.contains($0.id) }
            space.pinned.removeImported(ids)
            space.today.removeAll { ids.contains($0.id) }
            for id in space.split where ids.contains(id) { space.removeFromSplit(id) }
            for window in app.stores {
                if let selection = window.selectedTabIDs[space.id], ids.contains(selection) {
                    window.selectNeighbor(of: 0, in: space)
                }
            }
            app.discard(removed)
        }
        app.closedTabs.removeAll { ids.contains($0.record.id) }
        let archiveCount = app.archive.count
        app.archive.removeAll { ids.contains($0.tab.id) }
        if app.archive.count != archiveCount { app.saveArchive() }

        let newProfiles = Set(plan.newProfiles.map(\.id))
        for original in plan.newSpaces {
            guard let space = spaces.first(where: { $0.id == original.id }),
                  space.pinned.isEmpty, space.today.isEmpty,
                  space.name == original.name, space.hue == original.hue, space.symbol == original.symbol,
                  space.appearance == .auto,
                  !app.closedTabs.contains(where: { $0.spaceID == space.id }),
                  !app.archive.contains(where: { $0.spaceID == space.id }),
                  !settings.linkRoutes.contains(where: { $0.spaceID == space.id })
            else { continue }
            // Deleting the last space also erases cookies, history and favorites.
            if deletesProfile(space) {
                guard newProfiles.contains(space.profile.id), !space.profile.didOpenWebsiteData,
                      space.profile.favorites.isEmpty else { continue }
            }
            delete(space)
        }
    }
}

@MainActor
private extension Array where Element == SidebarItem {
    mutating func removeImported(_ ids: Set<UUID>) {
        removeAll { item in
            if case .folder(let folder) = item {
                folder.children.removeImported(ids)
                if !folder.children.isEmpty { return false }
            }
            return ids.contains(item.id)
        }
    }
}
