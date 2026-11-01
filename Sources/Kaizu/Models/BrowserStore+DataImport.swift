import BrowserCore
import SwiftUI

/// File → Import Browsing Data…: visited pages go to the space's profile,
/// where the command bar finds them; bookmarks become a closed pinned folder.
extension BrowserStore {
    /// `data`'s bookmarks that `space` doesn't already have pinned.
    func newBookmarks(in data: BrowsingData, named name: String, for space: Space) -> (folder: FolderRecord, count: Int)? {
        let tabs = space.pinned.tabs + space.profile.favorites
        return data.bookmarkFolder(named: name, skipping: Set(tabs.compactMap { $0.pinnedURL ?? $0.url }))
    }

    func importBrowsingData(_ visits: [BrowsingData.Visit], bookmarks: (folder: FolderRecord, count: Int)?, into space: Space) async {
        let profile = space.profile.id
        let added = await history?.add(visits, profile: profile) ?? []
        let item = bookmarks.map { app.makeItem(.folder($0.folder), profile: space.profile) }
        if let item {
            withAnimation(Motion.snap) { space.pinned.append(item) }
            scheduleSave()
        }

        let pages = visits.isEmpty ? nil : "\(visits.count.formatted()) \(visits.count == 1 ? "page" : "pages")"
        let marks = bookmarks.map { "\($0.count.formatted()) \($0.count == 1 ? "bookmark" : "bookmarks")" }
        let imported = [pages, marks].compactMap(\.self).joined(separator: " and ")
        showToast("Imported \(imported)", symbol: "square.and.arrow.down", undo: { [weak self] in
            guard let self else { return }
            // Pages that were here already stay, as they were left.
            Task { await self.history?.remove(added, profile: profile) }
            if let item {
                self.close([item].tabs)
                space.pinned.remove(id: item.id)
                self.scheduleSave()
            }
        }, lasts: .seconds(12))
    }
}
