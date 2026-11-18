import BrowserCore
import Foundation

extension BrowserStore {
    /// Remove exactly the items in this import, even if the user rearranged the sidebar in another window.
    func undoArcImport(_ plan: ArcImport) {
        app.removeImportedItems(plan.addedItemIDs)
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
