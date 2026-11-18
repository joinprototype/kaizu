import BrowserCore
import SwiftUI

/// File → Import Browsing Data…: visited pages go to the space's profile,
/// where the command bar finds them; bookmarks become a closed pinned folder.
extension AppModel {
    func importBrowsingData(_ visits: [BrowsingData.Visit], bookmarks: BookmarkImport?, into space: Space) async {
        let receipt: HistoryStore.ImportUndo?
        if visits.isEmpty {
            receipt = nil
        } else {
            guard let history else {
                regularFront.showToast("Couldn’t import pages because history is unavailable", symbol: "exclamationmark.triangle")
                return
            }
            do {
                receipt = try await history.importVisits(visits, profile: space.profile.id)
            } catch {
                regularFront.showToast("Couldn’t save the imported history", symbol: "exclamationmark.triangle")
                return
            }
        }
        let item = bookmarks.map { makeItem(.folder($0.folder), profile: space.profile) }
        let folderID = item?.id
        let imported = Set(item.map { [$0].tabs.map(\.id) } ?? [])
        if let item {
            withAnimation(Motion.snap) { space.pinned.append(item) }
            scheduleSave()
        }

        let pages = visits.isEmpty ? nil : visits.count.counted("page")
        let summary = [pages, bookmarks?.count.counted("bookmark")].compactMap(\.self).joined(separator: " and ")
        regularFront.showToast("Imported \(summary)", symbol: "square.and.arrow.down", undo: { [weak self] in
            guard let self else { return }
            if let receipt, let history = self.history {
                Task {
                    do {
                        try await history.undoImport(receipt)
                    } catch {
                        self.regularFront.showToast("Couldn’t undo the history import", symbol: "exclamationmark.triangle")
                    }
                }
            }
            if let folderID {
                self.removeImportedItems(imported, returningToTodayFrom: folderID)
                self.scheduleSave()
            }
        }, lasts: .seconds(12))
    }
}
