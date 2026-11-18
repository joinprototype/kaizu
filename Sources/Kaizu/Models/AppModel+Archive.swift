import BrowserCore
import SwiftUI

/// Arc-style auto-archive: today tabs left alone (12 hours by default) are put
/// away, and stay searchable (and reopenable) from the command bar.
extension AppModel {
    static let archiveLimit = 500
    private static let sweepInterval: Duration = .seconds(15 * 60)

    func startArchiving() {
        Task { [weak self] in
            while let self {
                self.archiveStaleTabs()
                try? await Task.sleep(for: Self.sweepInterval)
            }
        }
    }

    func archiveStaleTabs() {
        guard let interval = settings.archiveAfter.seconds else { return }
        let now = Date()
        let cutoff = now.addingTimeInterval(-interval)
        var archived: [ArchivedTabRecord] = []
        let notifying = notifyingTabs
        for space in spaces {
            // Keep visible tabs and ongoing media or notification sessions.
            let selected = Set(stores.compactMap { $0.selectedTabIDs[space.id] })
            let stale = space.today.filter { tab in
                !selected.contains(tab.id) && !space.split.contains(tab.id) && !tab.isPlayingMedia
                    && (tab.lastActiveAt ?? now) < cutoff
                    && !tab.isCapturingMedia && !notifying.contains(tab)
            }
            guard !stale.isEmpty else { continue }
            archived += stale.map { ArchivedTabRecord(tab: $0.record, spaceID: space.id, archivedAt: now) }
            withAnimation(Motion.snap) {
                space.today.removeAll { stale.contains($0) }
            }
            discard(stale)
        }
        guard !archived.isEmpty else { return }
        archive = Array((archived + archive).prefix(Self.archiveLimit))
        save()
        scheduleSave()
    }
}

extension BrowserStore {
    func matchingArchivedTabs(_ query: String) -> [ArchivedTabRecord] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return archive }
        let spaceNames = Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, $0.name) })
        return archive.filter { entry in
            [entry.tab.customTitle, entry.tab.title, entry.tab.url?.absoluteString, spaceNames[entry.spaceID]]
                .compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    func reopen(_ archived: ArchivedTabRecord) {
        guard !isPrivate,
              let space = spaces.first(where: { $0.id == archived.spaceID && $0.profile === activeSpace.profile }),
              let index = app.archive.firstIndex(where: { $0.id == archived.id && $0.spaceID == space.id })
        else { return }
        let entry = app.archive.remove(at: index)
        reopen(entry.tab, in: space)
        app.save()
    }
}
