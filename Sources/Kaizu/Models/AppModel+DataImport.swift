import BrowserCore
import DesignSystem
import SwiftUI

/// File → Import Browsing Data…: visited pages go to the space's profile,
/// where the command bar finds them; bookmarks become a closed pinned folder.
extension AppModel {
    func importBrowsingData(_ visits: [BrowsingData.Visit], bookmarks: BookmarkImport?, into space: Space) async {
        var receipt: HistoryStore.ImportUndo?
        var historyProblem: String?
        if !visits.isEmpty {
            if let history {
                do {
                    receipt = try await history.importVisits(visits, profile: space.profile.id)
                } catch {
                    historyProblem = "Couldn’t save the imported history"
                }
            } else {
                historyProblem = "Couldn’t import pages because history is unavailable"
            }
        }
        // Bookmarks don't depend on the history database, so a failed history write still brings them.
        if let historyProblem, bookmarks == nil {
            regularFront.showToast(historyProblem, symbol: "exclamationmark.triangle")
            return
        }
        let item = bookmarks.map { makeItem(.folder($0.folder), profile: space.profile) }
        let folderID = item?.id
        let imported = Set(item.map { [$0].tabs.map(\.id) } ?? [])
        if let item {
            withAnimation(Motion.snap) { space.pinned.append(item) }
            scheduleSave()
        }

        let pages = receipt == nil ? nil : visits.count.counted("page")
        let summary = [pages, bookmarks?.count.counted("bookmark")].compactMap(\.self).joined(separator: " and ")
        let message = historyProblem.map { "Imported \(summary). \($0)." } ?? "Imported \(summary)"
        let symbol = historyProblem == nil ? "square.and.arrow.down" : "exclamationmark.triangle"
        regularFront.showToast(message, symbol: symbol, undo: { [weak self] in
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
