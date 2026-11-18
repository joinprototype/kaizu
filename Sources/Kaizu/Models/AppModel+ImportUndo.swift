import Foundation

extension AppModel {
    /// Remove imported items from their current locations and repair references in all regular windows.
    /// A browsing-data import also returns later additions to its wrapper folder to Today.
    func removeImportedItems(_ ids: Set<UUID>, returningToTodayFrom bookmarkFolderID: UUID? = nil) {
        for profile in profiles {
            discard(profile.favorites.filter { ids.contains($0.id) })
            profile.favorites.removeAll { ids.contains($0.id) }
        }
        for space in spaces {
            let removed = (space.pinned.tabs + space.today).filter { ids.contains($0.id) }
            space.pinned.removeImported(ids)
            if let bookmarkFolderID, let item = space.pinned.remove(id: bookmarkFolderID) {
                // The folder still exists. Only tabs added to it after import remain.
                let kept = [item].tabs
                for tab in kept { tab.pinnedURL = nil }
                space.today.insert(contentsOf: kept, at: 0)
            }
            space.today.removeAll { ids.contains($0.id) }
            for id in space.split where ids.contains(id) { space.removeFromSplit(id) }
            for window in stores {
                if let selection = window.selectedTabIDs[space.id], ids.contains(selection) {
                    window.selectNeighbor(of: 0, in: space)
                }
            }
            discard(removed)
        }
        closedTabs.removeAll { ids.contains($0.record.id) }
        let archiveCount = archive.count
        archive.removeAll { ids.contains($0.tab.id) }
        if archive.count != archiveCount { save() }
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
