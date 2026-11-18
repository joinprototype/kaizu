#if DEBUG
import AppKit
import WebKit

extension DebugHooks {
    @MainActor static func checkPrivateBlocking(in store: BrowserStore) async {
        precondition(ProcessInfo.processInfo.environment["KAIZU_SUPPORT"] != nil)
        let app = store.app
        let blocker = store.contentBlocker
        let site = URL(string: "https://team.example.test/")!
        let parent = URL(string: "https://example.test/")!
        let previousPauses = blocker.pausedSites
        let first = app.openPrivateWindow()
        let second = app.openPrivateWindow()
        let regular = store.openTab(nil)
        let one = first.openTab(nil)
        let two = second.openTab(nil)
        let tabs = [regular, one, two]

        func toggle(_ url: URL, _ tab: BrowserTab) {
            blocker.togglePause(on: url, privateID: tab.profile.privateID)
        }
        func check(_ label: String, _ tab: BrowserTab, hidden: Bool) async {
            let token = UUID().uuidString
            let html = "<!doctype html><p id='control' data-token='\(token)'>Ordinary</p><div class='ADBox'>Ad</div>"
            tab.webView.loadSimulatedRequest(URLRequest(url: site), responseHTML: html)
            let script = """
                document.querySelector('#control')?.dataset.token === '\(token)' &&
                [getComputedStyle(document.querySelector('#control')).display,
                 getComputedStyle(document.querySelector('.ADBox')).display]
                """
            let expected = ["block", hidden ? "none" : "block"]
            for _ in 0..<100 {
                if let styles = try? await tab.webView.evaluateJavaScript(script) as? [String], styles == expected { return }
                try? await Task.sleep(for: .milliseconds(50))
            }
            print("FAILED: \(label), expected control and ad display \(expected)")
            exit(1)
        }
        await withCheckedContinuation { continuation in
            blocker.whenReady(for: site) { continuation.resume() }
        }
        toggle(parent, one)
        await check("private pause leaves regular protected", regular, hidden: true)
        await check("private pause covers its subdomain", one, hidden: false)
        await check("another private window stays protected", two, hidden: true)
        precondition(blocker.pausedSites == previousPauses)
        toggle(parent, one)
        toggle(parent, regular)
        toggle(site, one)
        await check("private resume preserves the regular pause", regular, hidden: false)
        await check("private resume protects the selected site", one, hidden: true)
        await check("the other window inherits the regular pause", two, hidden: false)
        let persisted = Set(UserDefaults.standard.stringArray(forKey: "blockingPausedSites") ?? [])
        precondition(persisted == previousPauses.union(["example.test"]))
        toggle(parent, regular)
        for tab in tabs { await check("removing the regular pause", tab, hidden: true) }
        toggle(site, one)
        first.window?.performClose(nil)
        let replacement = app.openPrivateWindow()
        await check("a new private window starts clean", replacement.openTab(nil), hidden: true)
        print("Verified regular and two private windows with independently rendered blocker rules")
        NSApp.terminate(nil)
    }
}
#endif
