#if DEBUG
import AppKit
import BrowserCore
import WebKit

extension DebugHooks {
    /// Exercise Undo across two regular windows, with new tabs and a saved login in an imported profile.
    static func checkArcImportUndo(in store: BrowserStore, file: URL) async throws {
        precondition(ProcessInfo.processInfo.environment["KAIZU_SUPPORT"] != nil)
        precondition(store.spaces.count == 1 && store.activeSpace.allTabs.isEmpty)
        var sidebar = try ArcSidebar.load(from: file)
        // Two extra spaces exercise Undo with and without website data. Neither gets a later tab.
        for name in ["Signed In", "Untouched"] {
            var space = sidebar.spaces[0]
            space.name = name
            space.profile = name
            sidebar.spaces.append(space)
        }
        let home = store.activeSpace
        let original = store.openTab(URL(string: "about:blank#original")!, select: false)
        let plan = store.arcImport(of: sidebar, includesToday: true)
        store.importFromArc(plan)
        let undo = store.toast!.undo!
        let design = store.spaces.first { $0.name == "Design" }!
        checkIncrementalArcImport(in: store, space: design, sidebar: sidebar)
        let imported = design.pinned.tabs[0]
        let folder = home.pinned.folders.first!
        store.move(original, to: .pinned(folder: folder, before: nil))
        let second = store.app.openWindow(on: design)
        let later = second.openTab(URL(string: "about:blank#later")!)
        second.newFolder(with: later)
        let favorite = second.openTab(URL(string: "about:blank#favorite")!)
        second.move(favorite, to: .favorites(before: nil))
        second.split(later, with: favorite.id, at: .pane(later.id, .right))
        second.split(favorite, with: imported.id, at: .pane(favorite.id, .bottom))
        precondition(second.shownTabs == [later, favorite, imported] && second.selectedTab === imported)

        let hidden = store.app.openPrivateWindow()
        let privateTab = hidden.openTab(URL(string: "about:blank#private")!)
        let signedIn = store.spaces.first { $0.name == "Signed In" }!
        let cookies = signedIn.profile.dataStore.httpCookieStore
        let cookie = HTTPCookie(properties: [
            .name: "session", .value: "test", .domain: "qa.invalid", .path: "/",
            .expires: Date().addingTimeInterval(3600)
        ])!
        await cookies.setCookie(cookie)
        undo()

        guard second.shownTabs == [later, favorite] && second.selectedTab === favorite else {
            FileHandle.standardError.write(Data("Undo hid the surviving split panes\n".utf8))
            exit(1)
        }
        precondition(hidden.activeSpace.today.contains(privateTab) && !privateTab.isDiscarded)
        precondition(home.pinned.tabs.contains(original) && !original.isDiscarded)
        precondition(design.pinned.tabs.contains(later) && !later.isDiscarded)
        precondition(design.profile.favorites.contains(favorite) && !favorite.isDiscarded)
        precondition(store.spaces.contains { $0 === design } && store.profiles.contains { $0 === design.profile })
        precondition(imported.isDiscarded && !design.allTabs.contains(imported))
        precondition(store.spaces.contains { $0 === signedIn } && signedIn.allTabs.isEmpty)
        let remainingCookies = await cookies.allCookies()
        precondition(remainingCookies.contains { $0.domain == "qa.invalid" && $0.name == "session" && $0.value == "test" })
        precondition(!store.spaces.contains { $0.name == "Untouched" })
        store.app.save()
        print("Arc import Undo preserved later edits, a favorite and a profile login, and removed the untouched space.")
    }

    private static func checkIncrementalArcImport(in store: BrowserStore, space: Space, sidebar: ArcSidebar) {
        let folder = space.pinned.folders.first { $0.name == "Type" }!
        let pin = folder.children.tabs[0]
        store.rename(pin, to: "My reference")
        folder.isExpanded = false
        pin.load(URL(string: "about:blank#later-page")!)
        let original = space.pinned.map(\.record)
        var updated = sidebar
        var design = sidebar.spaces.first { $0.name == "Design" }!
        let previous = design.pinned.tabs.first { $0.url == pin.pinnedURL }!
        var new = previous
        new.url = URL(string: "https://additional.example.test/")!
        design.pinned = [.folder(name: "Research", children: [.folder(name: "Type", children: [.tab(previous), .tab(new)])])]
        updated.spaces = [design]
        let addition = store.arcImport(of: updated, includesToday: true)
        precondition(addition.tabCount == 1)
        store.importFromArc(addition)
        precondition(folder.children.tabs.map(\.pinnedURL) == [pin.pinnedURL, new.url])
        precondition(space.pinned.folders.filter { $0.name == "Research" }.count == 1 && !folder.isExpanded)
        let undo = store.toast!.undo!
        precondition(store.arcImport(of: updated, includesToday: true).tabCount == 0)
        undo()
        precondition(space.pinned.map(\.record) == original)
        print("Repeat Arc import appended one nested pin and Undo restored the edited sidebar exactly.")
    }

    static func checkRestoredArcImportUndo(in store: BrowserStore) async {
        let design = store.spaces.first { $0.name == "Design" }!
        let personal = store.spaces.first { $0.name == "Personal" }!
        let signedIn = store.spaces.first { $0.name == "Signed In" }!
        precondition(store.spaces.count == 3 && store.profiles.count == 3)
        precondition(personal.pinned.tabs.map(\.pinnedURL?.fragment) == ["original"])
        precondition(design.pinned.tabs.map(\.pinnedURL?.fragment) == ["later"])
        precondition(design.profile.favorites.map(\.pinnedURL?.fragment) == ["favorite"])
        let restoredWindow = store.app.stores.first { $0.activeSpace === design }
        precondition(restoredWindow?.shownTabs.map(\.pinnedURL?.fragment) == ["later", "favorite"])
        precondition(restoredWindow?.selectedTab === design.profile.favorites.first)
        precondition(store.app.privateStores.isEmpty && signedIn.allTabs.isEmpty)
        let cookies = await signedIn.profile.dataStore.httpCookieStore.allCookies()
        precondition(cookies.contains { $0.domain == "qa.invalid" && $0.name == "session" && $0.value == "test" })
        print("After restart, Kaizu restored the edited folders, favorite and persistent profile cookie.")
    }
}
#endif
