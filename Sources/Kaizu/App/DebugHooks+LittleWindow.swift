#if DEBUG
import AppKit

extension DebugHooks {
    static func checkLittleWindowPromotion(in store: BrowserStore) async {
        precondition(ProcessInfo.processInfo.environment["KAIZU_SUPPORT"] != nil)
        let app = store.app
        let home = store.activeSpace
        let project = Space(profile: home.profile, name: "Project", symbol: "folder", hue: 0.5)
        app.spaces.append(project)
        let work = app.openWindow(on: project)
        let url = URL(string: "about:blank#draft")!
        let tab = work.openLittleWindow(url)
        let little = app.littleWindows.last!
        let view = tab.webView
        for _ in 0..<200 {
            if view.url == url, !view.isLoading { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        func check(_ condition: Bool, _ message: String) {
            guard condition else {
                log("FAILED: \(message)")
                exit(1)
            }
        }
        check(view.url == url && !view.isLoading, "fixture page completed loading")
        _ = try? await view.evaluateJavaScript("window.kaizuDraft = 'unfinished note'")
        func focus(_ window: NSWindow?) async {
            guard let window else { check(false, "expected a browser window"); return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            for _ in 0..<100 where !window.isKeyWindow {
                try? await Task.sleep(for: .milliseconds(50))
            }
            check(window.isKeyWindow, "AppKit focus (active=\(NSApp.isActive), visible=\(window.isVisible), canBecomeKey=\(window.canBecomeKey))")
        }
        check(work !== store, "two independent regular windows opened")
        await focus(store.window)
        let file = NSApp.mainMenu!.item(withTitle: "File")!.submenu!
        let promote = file.item(withTitle: "Open Little Window in Kaizu")!
        file.update()
        check(!promote.isEnabled, "promotion requires a focused little window")
        await focus(little.window)
        file.update()
        check(promote.isEnabled && promote.keyEquivalent == "o", "promotion is available on Command-O")
        file.performActionForItem(at: file.index(of: promote))
        check(project.today.contains(tab) && !home.today.contains(tab), "promotion returned to its opening space")
        check(work.selectedTab === tab && store.activeSpace === home, "promotion preserved the other window")
        for _ in 0..<100 where view.window !== work.window {
            try? await Task.sleep(for: .milliseconds(50))
        }
        check(view.window === work.window, "promoted page appeared in the destination window")
        let draft = try? await tab.webView.evaluateJavaScript("window.kaizuDraft") as? String
        check(tab.webView === view && draft == "unfinished note", "live page state survived promotion")
        little.promote()
        check(project.today.filter { $0 === tab }.count == 1, "repeated promotion kept a single tab")

        let third = app.openWindow(on: project)
        let fromClosed = third.openLittleWindow(URL(string: "about:blank#closed-window"))
        let orphan = app.littleWindows.last!
        third.window?.close()
        app.front = store
        orphan.promote()
        check(work.selectedTab === fromClosed && store.activeSpace === home, "a closed opener used the window on Project")

        let survivor = work.openLittleWindow(URL(string: "about:blank#survivor"))
        let survivingWindow = app.littleWindows.last!
        store.delete(project)
        survivingWindow.promote()
        check(home.today.contains(survivor) && survivor.profile === home.profile, "surviving profile received its page")

        let client = Profile(name: "Client")
        let clientSpace = Space(profile: client, name: "Client", symbol: "folder", hue: 0.2)
        app.profiles.append(client)
        app.spaces.append(clientSpace)
        work.switchTo(clientSpace)
        let removed = work.openLittleWindow(URL(string: "about:blank#removed-profile"))
        let removedWindow = app.littleWindows.last!
        let kept = store.openLittleWindow(URL(string: "about:blank#kept-profile"))
        store.delete(clientSpace)
        check(!app.littleWindows.contains { $0 === removedWindow }, "deleting a profile closed its little window")
        removedWindow.promote()
        check(!home.today.contains(removed) && !removed.isLoaded, "removed profile stayed out of the workspace")
        check(app.littleWindows.contains { $0.tab === kept }, "deleting another profile preserved this little window")
        log("Little-window promotion preserved the live page and its profile.")
        NSApp.terminate(nil)
    }
}
#endif
