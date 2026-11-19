#if DEBUG
import AppKit
import BrowserCore
import DesignSystem
import WebKit

extension DebugHooks {
    /// Run against a scratch session with KAIZU_DEBUG=tabsearch.
    static func qaTabSearch(_ store: BrowserStore) {
        let app = store.app
        let home = store.activeSpace
        let work = Space(profile: home.profile, name: "Work", symbol: "briefcase", hue: 0.5)
        let foreign = Space(profile: Profile(name: "Other"), name: "Other", symbol: "star", hue: 0)
        app.profiles.append(foreign.profile)
        app.spaces += [work, foreign]
        let privateStore = app.openPrivateWindow()
        let url = URL(string: "about:blank#qa-tab-search")!
        let selected = store.openTab(url)
        let favorite = store.openTab(url, select: false)
        store.move(favorite, to: .favorites(before: nil))
        let target = store.openTab(url, in: work, select: false)
        let folder = Folder(name: "Reading", isExpanded: false)
        work.pinned = [.folder(folder)]
        store.move(target, to: .pinned(folder: folder, before: nil), in: work)
        target.customTitle = "QA notes"
        let other = store.openTab(url, in: foreign, select: false)
        let hidden = privateStore.openTab(url, select: false)
        app.archive.append(ArchivedTabRecord(tab: other.record, spaceID: foreign.id, archivedAt: .now))

        let matches = store.matchingTabs("qa-tab-search", acrossSpaces: true)
        precondition(matches.map(\.tab.id) == [favorite.id, target.id])
        precondition(matches.map(\.space.id) == [home.id, work.id])
        precondition(store.selectedTab === selected && !target.isLoaded)
        precondition(store.matchingTabs("QA notes", acrossSpaces: false).isEmpty)
        precondition(privateStore.matchingTabs("qa-tab-search", acrossSpaces: true).map(\.tab.id) == [hidden.id])
        precondition(!store.archive.contains { $0.spaceID == foreign.id } && privateStore.archive.isEmpty)

        let match = store.matchingTabs("qa NOTES", acrossSpaces: true).first!
        let suggestion = Suggestion.tab(match.tab, in: match.space)
        precondition(suggestion.presentation(searchEngine: store.settings.searchEngine).subtitle?.contains("Work") == true)
        store.perform(suggestion, mode: .newTab)
        precondition(store.activeSpace === work && store.selectedTab === target)
        precondition(work.pinned.tabs == [target] && work.today.isEmpty)
        FileHandle.standardError.write(Data("QA tab search passed\n".utf8))
        NSApp.terminate(nil)
    }

    static func qaTabMoves(_ store: BrowserStore) {
        func check(_ name: String, _ passed: Bool) {
            FileHandle.standardError.write(Data("QA tabs \(passed ? "ok" : "FAILED"): \(name)\n".utf8))
        }
        Task {
            if let named = store.spaces.flatMap(\.allTabs).first(where: { $0.customTitle != nil }) {
                check("a name comes back after quitting", named.displayTitle == "My page")
                return NSApp.terminate(nil)
            }
            let home = store.activeSpace
            let page = URL(string: "https://example.com/")!
            let tab = store.openTab(page)
            await loaded(tab)
            _ = await until(3) { tab.title == tab.webView.title }
            let pageTitle = tab.title
            store.rename(tab, to: "  My page ")
            check("a tab takes a name", tab.displayTitle == "My page" && tab.title == pageTitle)
            store.rename(tab, to: "   ")
            check("no name goes back to the page's", tab.customTitle == nil && tab.displayTitle == pageTitle)
            store.rename(tab, to: "My page")

            store.commit(SpaceDraft(name: "Same profile", hue: Theme.all[1].hue, symbol: Space.symbols[1], profile: .existing(home.profile.id)))
            let same = store.activeSpace
            store.commit(SpaceDraft(name: "Other profile", hue: Theme.all[2].hue, symbol: Space.symbols[2], profile: .new))
            let other = store.activeSpace
            store.switchTo(home)
            try? await Task.sleep(for: .seconds(1))

            let webView = tab.webView
            let stay = store.openTab(URL(string: "https://example.com/stay"))
            store.select(tab)
            store.move(tab, toSpace: same)
            check("moved within a profile it stays live", await until(3) { same.today.contains(tab) && !home.today.contains(tab) && tab.webView === webView && !tab.isDiscarded })
            check("the window moves on", await until(3) { store.selectedTab === stay })

            store.switchTo(same)
            store.move(tab, toSpace: other)
            _ = await until(3) { tab.isDiscarded && other.today.first != nil }
            let reopened = other.today.first
            check("across profiles it reopens there", tab.isDiscarded && same.today.isEmpty && reopened?.profile === other.profile && reopened?.url == tab.url)
            check("with its name", reopened?.displayTitle == "My page")
            check("nothing selected where it left", store.selectedTab == nil)
            store.switchTo(home)
            let named = store.openTab(URL(string: "https://example.org/named"))
            store.rename(named, to: "Named")
            store.close(named)
            store.reopenClosedTab()
            check("⇧⌘T keeps a tab's name", await until(3) { store.selectedTab?.customTitle == "Named" })
            let beforeClear = home.today.map(\.displayTitle)
            store.clearToday(in: home)
            store.reopenClosedTab()
            store.undoToast()
            check("Clear, reopen and Undo return every tab exactly once", home.today.map(\.displayTitle) == beforeClear)
            try? await Task.sleep(for: .seconds(1))
            NSApp.terminate(nil)
        }
    }
}
#endif
