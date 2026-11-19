#if DEBUG
import AppKit
import BrowserCore
import DesignSystem
import WebKit

extension DebugHooks {
    static func qaPrivateWindow(_ store: BrowserStore) {
        let app = store.app
        func check(_ name: String, _ passed: Bool) {
            FileHandle.standardError.write(Data("QA private \(passed ? "ok" : "FAILED"): \(name)\n".utf8))
        }
        func settle(_ seconds: Double = 0.5) async {
            try? await Task.sleep(for: .seconds(seconds))
        }
        Task {
            let site = URL(string: "https://example.org/")!
            let regular = store.openTab(site)
            await loaded(regular)
            let hidden = app.openPrivateWindow()
            check("it's a window of its own, in front", await until { hidden.isPrivate && app.front === hidden && app.regularFront === store })
            check("its space isn't shared", !app.spaces.contains { $0 === hidden.activeSpace } && hidden.spaces.count == 1)
            check("its profile is in memory", hidden.activeSpace.profile.isPrivate && !hidden.activeSpace.profile.dataStore.isPersistent)
            check("it's dark", await until { hidden.window?.appearance?.name == .darkAqua })

            let one = hidden.openTab(URL(string: "https://example.org/private-page"))
            await loaded(one)
            check("a page opens in it", await until { hidden.selectedTab === one && one.webView.window === hidden.window })
            let two = hidden.openTab(site, after: one, select: false)
            check("and more tabs", hidden.activeSpace.today.count == 2 && two.profile === one.profile)

            saveShot(of: hidden.window)
            let cookie = "document.cookie = 'kaizu=private'; document.cookie"
            _ = try? await one.webView.evaluateJavaScript(cookie)
            let outside = (try? await regular.webView.evaluateJavaScript("document.cookie")) as? String ?? "?"
            check("its cookies stay in it", !outside.contains("kaizu=private"))

            hidden.close(two)
            hidden.reopenClosedTab()
            check("⇧⌘T works inside it", await until { hidden.activeSpace.today.count == 2 && app.closedTabs.isEmpty })

            let secret = URL(string: "https://example.org/private-page")!
            hidden.select(two)
            app.front = store
            check("a page off screen stays with its private window", one.store === hidden)
            check("an ordinary one with the ordinary windows", store.selectedTab !== regular || regular.store === store)
            let others = app.openPrivateWindow()
            others.window?.performClose(nil)
            await settle()
            check("and a second private window doesn't take it", one.store === hidden)
            hidden.window?.makeKeyAndOrderFront(nil)
            app.front = hidden
            hidden.select(one)
            await settle()

            hidden.toggleBlockingOnCurrentSite(one)
            let saved = AppDefaults.shared.stringArray(forKey: "blockingPausedSites") ?? []
            check("pausing blocking there isn't saved", store.contentBlocker.isPaused(on: secret, privateID: one.profile.privateID) && !store.contentBlocker.isPaused(on: secret, privateID: nil) && !saved.contains("example.org") && !store.contentBlocker.pausedSites.contains("example.org"))

            let closing = hidden.openTab(URL(string: "https://example.org/closing"))
            _ = await until { hidden.selectedTab === closing }
            hidden.close(closing)
            check("closing a tab there moves to its neighbor", await until { hidden.selectedTab != nil })

            hidden.togglePin(one)
            hidden.newFolder()
            check("nothing pins there", hidden.activeSpace.pinned.isEmpty)
            check("the archive isn't offered there", hidden.archive.isEmpty)

            let count = hidden.activeSpace.today.count
            app.regularFront.openExternal(URL(string: "https://example.org/from-another-app")!)
            await settle()
            check("links from other apps skip it", hidden.activeSpace.today.count == count)
            let littleWindows = app.littleWindows.count
            hidden.openLittleWindow(URL(string: "https://example.org/little"))
            check("a little window from it stays inside it", await until { app.littleWindows.count == littleWindows && hidden.activeSpace.today.count == count + 1 })

            app.save()
            let session = (try? String(contentsOf: AppPaths.support.appending(path: "session.json"), encoding: .utf8)) ?? ""
            check("the session doesn't mention it", session.contains("example.org") && !session.contains("private-page") && !session.contains("\"Private\""))
            let stored = await store.history?.search("private-page", profile: hidden.activeSpace.profile.id) ?? []
            let shared = await store.history?.search("private-page", profile: store.activeSpace.profile.id) ?? []
            check("history doesn't either", stored.isEmpty && shared.isEmpty)
            app.updateSpotlight()
            check("nor Spotlight", !app.spotlightIdentifiers.contains(one.id.uuidString))

            let ordinary = app.openWindow()
            check("⌘N from it is an ordinary window", await until { !ordinary.isPrivate && app.stores.contains { $0 === ordinary } })
            ordinary.window?.performClose(nil)
            hidden.window?.makeKeyAndOrderFront(nil)
            app.front = hidden
            await settle()

            hidden.window?.performClose(nil)
            check("closing it ends it", await until { app.privateStores.isEmpty && one.isDiscarded && hidden.window == nil })
            check("and the ordinary window is in front again", await until(3) { app.front === store })
            check("a site paused there is forgotten", !store.contentBlocker.isPaused(on: secret, privateID: nil))
            NSApp.terminate(nil)
        }
    }

    static func qaWindows(_ store: BrowserStore) {
        let app = store.app
        func check(_ name: String, _ passed: Bool) {
            FileHandle.standardError.write(Data("QA windows \(passed ? "ok" : "FAILED"): \(name)\n".utf8))
        }
        func settle() async {
            try? await Task.sleep(for: .milliseconds(500))
        }
        func page(_ path: String) -> URL? {
            URL(string: "https://example.com/\(path)")
        }
        Task {
            if app.stores.count > 1 {
                let second = app.stores[1]
                let saved = second.savedFrame
                check("two windows came back", await until(3) { app.stores.count == 2 })
                check("each window kept its own tab", store.selectedTab != nil && second.selectedTab != nil && store.selectedTab !== second.selectedTab)
                check("second window kept its place", saved != nil && second.window?.frameDescriptor == saved)
                check("first window kept its place", store.savedFrame != nil && store.window?.frameDescriptor == store.savedFrame)
                second.window?.performClose(nil)
                check("closing a window leaves its tabs in the sidebar", await until(3) { app.stores.count == 1 && store.activeSpace.today.count == 4 })
                store.window?.performClose(nil)
                check("the last window only hides", await until(3) { app.stores.count == 1 && store.window?.isVisible == false })
                check("⌘N brings it back instead of leaving it hidden", app.openWindow() === store && app.stores.count == 1)
                check("with its page", await until(3) { store.window?.isVisible == true && store.selectedTab != nil })
                return NSApp.terminate(nil)
            }

            let one = store.openTab(page("one"))
            let two = store.openTab(page("two"), select: false)
            _ = await until(3) { store.selectedTab === one && one.webView.window === store.window }
            let second = app.openWindow()
            check("a new window starts on the same space, empty, in front", await until(3) { second.activeSpaceID == store.activeSpaceID && second.selectedTab == nil && app.front === second })
            check("and off to the side of the last", second.window?.frame != store.window?.frame)

            second.perform(.url(page("typed")!), mode: .newTab)
            _ = await until(3) { second.selectedTab?.url?.lastPathComponent == "typed" && second.selectedTab?.webView.window === second.window }
            let typed = second.selectedTab
            check("a page opened from the command bar opens in that window", typed?.url?.lastPathComponent == "typed" && typed?.webView.window === second.window)
            check("and the other window keeps its page", store.selectedTab === one && one.webView.window === store.window)
            store.settings.linkRoutes = [LinkRoute(pattern: "example.com", spaceID: second.activeSpaceID)]
            app.front.openExternal(page("routed")!)
            _ = await until(3) { second.selectedTab?.url?.lastPathComponent == "routed" }
            let routed = second.selectedTab
            check("a link routed to this space opens in the window in front", routed?.url?.lastPathComponent == "routed" && store.selectedTab === one)
            store.settings.linkRoutes = []
            typed.map(second.close)
            routed.map(second.close)

            second.select(two)
            check("each window shows its own tab", await until(3) { second.selectedTab === two && two.webView.window === second.window && one.webView.window === store.window })

            second.select(one)
            check("selecting a tab shown elsewhere brings that window forward", await until(3) { app.front === store && second.selectedTab === two })
            check("as the key window, when Kaizu is the active app", await until(3) { !NSApp.isActive || store.window?.isKeyWindow == true })

            store.close(two)
            check("closing a tab never steals one from another window", await until(3) { second.selectedTab == nil && store.selectedTab === one })

            let three = second.openTab(page("three"))
            _ = await until(3) { second.selectedTab === three && three.webView.window === second.window }
            store.moveToNewWindow(one)
            _ = await until(3) { app.stores.count == 3 && one.webView.window === app.stores[2].window && store.selectedTab == nil }
            let third = app.stores[2]
            check("a tab can move to a window of its own", third.selectedTab === one)
            check("its page goes with it", one.webView.window === third.window)
            check("the window it left has nothing free to show", store.selectedTab == nil)

            let four = store.openTab(page("four"))
            _ = await until(3) { store.selectedTab === four && four.webView.window === store.window }
            store.addToSplit(three)
            check("a split takes its pane from the window showing it", await until(3) { second.selectedTab == nil && three.webView.window === store.window && four.webView.window === store.window })
            check("and leaves no page behind", third.window?.isVisible == true && one.webView.window === third.window)
            third.select(three)
            check("a split shows in one window", await until(3) { third.selectedTab === one && app.front === store })
            let five = third.openTab(page("five"))
            _ = await until(3) { third.selectedTab === five && five.webView.window === third.window }
            let split = store.activeSpace.split
            third.addToSplit(one)
            third.closeSplit()
            check("a window leaves another's split alone", store.activeSpace.split == split && third.selectedTab === five)
            third.select(one)
            await settle()
            store.closeSplit()
            store.select(four)
            await settle()

            let home = store.activeSpace
            store.commit(SpaceDraft(name: "Work", hue: Theme.all[1].hue, symbol: Space.symbols[1], profile: .existing(home.profile.id)))
            await settle()
            second.select(four)
            store.switchTo(home)
            check("a tab another window took isn't selected any more", await until(3) { store.selectedTab == nil && second.selectedTab === four })

            let empty = app.openWindow()
            await settle()
            empty.addToSplit(four)
            await settle()
            check("a window with nothing to split with takes nothing", second.selectedTab === four && empty.selectedTab == nil)
            empty.window?.performClose(nil)
            await settle()

            let work = store.spaces.last ?? home
            let favorite = store.openTab(page("favorite"))
            store.move(favorite, to: .favorites(before: nil))
            await settle()
            second.switchTo(work)
            second.select(favorite)
            await settle()
            store.switchTo(home)
            store.moveToNewWindow(favorite)
            _ = await until(3) { app.stores.last.map { $0.selectedTab === favorite && favorite.webView.window === $0.window } == true && second.selectedTab == nil }
            let fourth = app.stores[app.stores.count - 1]
            check("a favorite shown on another space moves out too", fourth.selectedTab === favorite && favorite.webView.window === fourth.window && second.selectedTab == nil)
            fourth.window?.performClose(nil)
            await settle()
            second.switchTo(home)
            second.select(four)
            await settle()

            third.select(five)
            await settle()
            five.lastActiveAt = .distantPast
            third.window?.performClose(nil)
            await settle()
            store.select(one)
            check("a closed window's tabs can show elsewhere", await until(3) { app.stores.count == 2 && one.webView.window === store.window })
            check("and count as just used", five.lastActiveAt.map { -$0.timeIntervalSinceNow < 60 } == true)

            store.window?.setFrameOrigin(NSPoint(x: 240, y: 60))
            second.window?.setFrameOrigin(NSPoint(x: 200, y: 90))
            NSApp.terminate(nil)
        }
    }
}
#endif
