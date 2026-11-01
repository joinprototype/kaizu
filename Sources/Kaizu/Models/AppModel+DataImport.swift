import BrowserCore
import SwiftUI

/// File → Import Browsing Data…: visited pages go to the space's profile,
/// where the command bar finds them; bookmarks become a closed pinned folder.
extension AppModel {
    func importBrowsingData(_ visits: [BrowsingData.Visit], bookmarks: BookmarkImport?, into space: Space) async {
        let profile = space.profile.id
        let added = await history?.add(visits, profile: profile) ?? []
        let item = bookmarks.map { makeItem(.folder($0.folder), profile: space.profile) }
        let imported = Set(item.map { [$0].tabs.map(\.id) } ?? [])
        if let item {
            withAnimation(Motion.snap) { space.pinned.append(item) }
            scheduleSave()
        }

        let pages = visits.isEmpty ? nil : visits.count.counted("page")
        let summary = [pages, bookmarks?.count.counted("bookmark")].compactMap(\.self).joined(separator: " and ")
        regularFront.showToast("Imported \(summary)", symbol: "square.and.arrow.down", undo: { [weak self] in
            guard let self else { return }
            // Pages that were here already stay, as they were left.
            Task { await self.history?.remove(added, profile: profile) }
            if let item {
                // Anything moved into the folder since goes to Today.
                let tabs = [item].tabs
                space.pinned.remove(id: item.id)
                self.discard(tabs.filter { imported.contains($0.id) })
                for tab in tabs where !imported.contains(tab.id) {
                    tab.pinnedURL = nil
                    space.today.insert(tab, at: 0)
                }
                self.scheduleSave()
            }
        }, lasts: .seconds(12))
    }
}
