#if DEBUG
import AppKit
import BrowserCore
import Darwin

extension DebugHooks {
    @MainActor static func interruptArchiveSweep(in store: BrowserStore) {
        precondition(ProcessInfo.processInfo.environment["KAIZU_SUPPORT"] != nil)
        let app = store.app
        let work = store.activeSpace
        precondition(work.name == "Work")
        let hidden = app.openPrivateWindow()
        let stale = store.openTab(URL(string: "about:blank#stale"), in: work, select: false)
        let secret = hidden.openTab(URL(string: "about:blank#private"), select: false)
        app.settings.archiveAfter = .twelveHours
        stale.lastActiveAt = .distantPast
        secret.lastActiveAt = .distantPast
        app.save()
        app.archiveStaleTabs()
        precondition(!work.today.contains(stale) && hidden.activeSpace.today.contains(secret))
        precondition(app.archive.contains { $0.id == stale.id && $0.spaceID == work.id })
        _exit(0)
    }

    /// The fixture starts with a legacy session and two archived copies of the same URL in different profiles.
    @MainActor static func checkArchiveRecovery(in store: BrowserStore, interrupt: Bool) {
        precondition(ProcessInfo.processInfo.environment["KAIZU_SUPPORT"] != nil)
        let app = store.app
        let work = store.spaces.first { $0.name == "Work" }!
        let other = app.archive.first { $0.tab.customTitle == "Other profile" }!
        let hidden = app.openPrivateWindow()
        precondition(hidden.archive.isEmpty && !store.archive.contains(other))
        hidden.reopen(other)
        store.reopen(other)
        precondition(app.archive.contains(other))
        if interrupt {
            precondition(store.activeSpace.name == "Home")
            let target = store.matchingArchivedTabs(" quarterly ").first!
            precondition(store.matchingArchivedTabs("work") == [target])
            precondition(store.matchingArchivedTabs("same-page") == [target] && hidden.matchingArchivedTabs("quarterly").isEmpty)
            precondition(Suggestion.archived(target).presentation(searchEngine: store.settings.searchEngine).title == "Quarterly notes")
            store.perform(.archived(target), mode: .newTab)
            precondition(store.activeSpace === work && store.selectedTab?.customTitle == target.tab.customTitle)
            precondition(!app.archive.contains(target))
            // Simulate a process loss before the throttled session save or quit handler runs.
            _exit(0)
        }
        precondition(store.activeSpace === work && store.selectedTab?.customTitle == "Quarterly notes")
        precondition(work.today.count == 1 && work.today[0].profile === work.profile)
        precondition(work.today[0].url == other.tab.url)
        precondition(app.archive == [other] && store.archive.isEmpty)
        NSApp.terminate(nil)
    }
}
#endif
