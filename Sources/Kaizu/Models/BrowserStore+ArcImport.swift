import BrowserCore
import SwiftUI

/// File → Import from Arc…: what `ArcImport` plans, applied to the live store.
extension BrowserStore {
    func arcImport(of sidebar: ArcSidebar, includesToday: Bool) -> ArcImport {
        ArcImport(
            sidebar, profiles: profiles.map(\.record), spaces: spaces.map { $0.record() }, includesToday: includesToday,
            hues: Theme.all.map(\.hue), symbols: Space.symbols
        )
    }

    func importFromArc(_ plan: ArcImport) {
        profiles += plan.newProfiles.map { record in
            let profile = Profile(id: record.id, name: record.name)
            profile.favorites = record.favorites.map { app.makeTab($0, profile: profile) }
            return profile
        }
        var favorites: [(profile: Profile, ids: Set<UUID>)] = []
        for (id, records) in plan.favorites {
            guard let profile = profiles.first(where: { $0.id == id }) else { continue }
            let tabs = records.map { app.makeTab($0, profile: profile) }
            profile.favorites += tabs
            favorites.append((profile, Set(tabs.map(\.id))))
        }
        var sections: [(space: Space, ids: Set<UUID>)] = []
        for space in spaces {
            let items = (plan.pinned[space.id] ?? []).map { app.makeItem($0, profile: space.profile) }
            let today = (plan.today[space.id] ?? []).map { app.makeTab($0, profile: space.profile) }
            space.pinned += items
            space.today += today
            if !items.isEmpty || !today.isEmpty {
                sections.append((space, Set(items.map(\.id) + today.map(\.id))))
            }
        }
        let renamed = plan.takeover.flatMap { takeover in
            spaces.first { $0.id == takeover.spaceID }.map { space in
                let before = (space, space.name, space.hue)
                space.name = takeover.name
                space.hue = takeover.hue ?? space.hue
                return before
            }
        }
        let newSpaces = plan.newSpaces.compactMap { record -> Space? in
            guard let profile = profiles.first(where: { $0.id == record.profileID }) else { return nil }
            let space = Space(id: record.id, profile: profile, name: record.name, symbol: record.symbol, hue: record.hue)
            space.pinned = record.pinned.map { app.makeItem($0, profile: profile) }
            space.today = record.today.map { app.makeTab($0, profile: profile) }
            return space
        }
        withAnimation(Motion.snap) { spaces += newSpaces }
        scheduleSave()

        let count = plan.tabCount
        showToast("Imported \(count) \(count == 1 ? "tab" : "tabs") from Arc", symbol: "square.and.arrow.down", undo: { [weak self] in
            guard let self else { return }
            newSpaces.forEach(self.delete)
            for (profile, ids) in favorites {
                self.close(profile.favorites.filter { ids.contains($0.id) })
                profile.favorites.removeAll { ids.contains($0.id) }
            }
            for (space, ids) in sections {
                let items = space.pinned.filter { ids.contains($0.id) }
                self.close(items.tabs + space.today.filter { ids.contains($0.id) })
                space.pinned.removeAll { ids.contains($0.id) }
                space.today.removeAll { ids.contains($0.id) }
            }
            if let (space, name, hue) = renamed {
                space.name = name
                space.hue = hue
            }
            self.scheduleSave()
        }, lasts: .seconds(12))
    }

    private func close(_ tabs: [BrowserTab]) {
        for tab in tabs {
            extensions.didClose(tab)
            tab.discard()
        }
    }
}
