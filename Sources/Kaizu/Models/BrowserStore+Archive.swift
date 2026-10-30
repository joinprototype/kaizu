import BrowserCore
import SwiftUI

/// Arc-style auto-archive: today tabs left alone (12 hours by default) are put
/// away, and stay searchable (and reopenable) from the command bar.
extension BrowserStore {
    static let archiveLimit = 500
    private static let sweepInterval: Duration = .seconds(15 * 60)

    private static var archiveURL: URL {
        AppPaths.support.appending(path: "archive.json")
    }

    func startArchiving() {
        Task { [weak self] in
            while let self {
                self.archiveStaleTabs()
                try? await Task.sleep(for: Self.sweepInterval)
            }
        }
    }

    func archiveStaleTabs(now: Date = Date()) {
        guard let interval = settings.archiveAfter.seconds else { return }
        let cutoff = now.addingTimeInterval(-interval)
        var archived: [ArchivedTabRecord] = []
        for space in spaces {
            // Anything on screen or audible stays, however long it's been.
            let stale = space.today.filter { tab in
                tab.id != space.selectedTabID && !space.split.contains(tab.id) && tab !== peek && !tab.isPlayingMedia
                    && (tab.lastActiveAt ?? now) < cutoff
            }
            guard !stale.isEmpty else { continue }
            archived += stale.map { ArchivedTabRecord(tab: $0.record, spaceID: space.id, archivedAt: now) }
            withAnimation(Motion.snap) {
                space.today.removeAll { stale.contains($0) }
            }
            for tab in stale {
                extensions.didClose(tab)
                tab.discard()
            }
        }
        guard !archived.isEmpty else { return }
        archive = Array((archived + archive).prefix(Self.archiveLimit))
        saveArchive()
        scheduleSave()
    }

    func reopen(_ archived: ArchivedTabRecord) {
        archive.removeAll { $0.id == archived.id }
        let space = spaces.first { $0.id == archived.spaceID } ?? activeSpace
        openTab(archived.tab.url, in: space).title = archived.tab.title
        saveArchive()
    }

    func loadArchive() {
        guard let data = try? Data(contentsOf: Self.archiveURL) else { return }
        archive = (try? JSONCoding.decoder.decode([ArchivedTabRecord].self, from: data)) ?? []
    }

    func saveArchive() {
        do {
            try JSONCoding.encoder.encode(archive).write(to: Self.archiveURL, options: .atomic)
        } catch {
            Log.session.error("Couldn't save archived tabs: \(error.localizedDescription, privacy: .public)")
        }
    }
}
