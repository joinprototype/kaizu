#if DEBUG
import AppKit
import WebKit

extension DebugHooks {
    static func checkPrivateBlocking(in store: BrowserStore) async throws {
        precondition(ProcessInfo.processInfo.environment["KAIZU_SUPPORT"] != nil)
        func report(_ message: String) {
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
        report("Opening private and regular test windows")
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
        func check(_ label: String, _ tab: BrowserTab, hidden: Bool, listEnabled: Bool = true) async {
            report(label)
            let token = UUID().uuidString
            let html = "<!doctype html><p id='control' data-token='\(token)'>Ordinary</p><div class='ADBox'>Ad</div><div class='kaizu-custom-fixture'>Custom</div>"
            tab.webView.loadSimulatedRequest(URLRequest(url: site), responseHTML: html)
            let script = """
                document.querySelector('#control')?.dataset.token === '\(token)' &&
                [getComputedStyle(document.querySelector('#control')).display,
                 getComputedStyle(document.querySelector('.ADBox')).display,
                 getComputedStyle(document.querySelector('.kaizu-custom-fixture')).display]
                """
            let expected = ["block", hidden ? "none" : "block", hidden && listEnabled ? "none" : "block"]
            var lastStyles: [String]?
            for _ in 0..<100 {
                if let styles = try? await tab.webView.evaluateJavaScript(script) as? [String] {
                    lastStyles = styles
                    if styles == expected { return }
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            report("FAILED: \(label), expected control, bundled and imported display \(expected), received \(String(describing: lastStyles))")
            exit(1)
        }
        report("Waiting for bundled rules")
        await withCheckedContinuation { continuation in
            blocker.whenReady(for: site) { continuation.resume() }
        }
        let lists = blocker.importedLists
        let rules = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        let json = #"[{"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".kaizu-custom-fixture"}}]"#
        defer { try? FileManager.default.removeItem(at: rules) }
        try json.write(to: rules, atomically: true, encoding: .utf8)
        report("Importing a custom rule list")
        try await lists.add(rules)
        let listID = lists.entries.first { $0.name == rules.lastPathComponent }!.id
        toggle(parent, one)
        await check("private pause leaves regular protected", regular, hidden: true)
        await check("private pause covers its subdomain", one, hidden: false)
        await check("another private window stays protected", two, hidden: true)
        try await lists.setEnabled(false, id: listID)
        await check("disabling the list leaves bundled rules active", regular, hidden: true, listEnabled: false)
        try await lists.setEnabled(true, id: listID)
        await check("reinstall keeps the private pause", one, hidden: false)
        await check("reinstall keeps the other private window protected", two, hidden: true)
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
        try await lists.remove(listID)
        report("Verified regular and two private windows with independently rendered bundled and imported rules")
    }
}
#endif
