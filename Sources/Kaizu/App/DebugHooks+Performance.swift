#if DEBUG
import AppKit
import BrowserCore
import WebEngine
import WebKit

extension DebugHooks {
    /// Opens KAIZU_SITES (comma separated) in tabs, optionally hibernates them
    /// (KAIZU_HIBERNATE), closes them, KAIZU_ROUNDS times. Waits KAIZU_SETTLE
    /// seconds after each step, so footprints can be read from outside.
    static func qaMemory(_ store: BrowserStore) {
        let environment = ProcessInfo.processInfo.environment
        let sites = (environment["KAIZU_SITES"] ?? "").split(separator: ",").compactMap { URL(string: String($0)) }
        let rounds = environment["KAIZU_ROUNDS"].flatMap(Int.init) ?? 1
        let settle = environment["KAIZU_SETTLE"].flatMap(Int.init) ?? 20
        func step(_ text: String) async {
            DebugHooks.log("QA memory: \(text)")
            try? await Task.sleep(for: .seconds(settle))
        }
        Task {
            await step("start")
            for round in 1...rounds {
                var tabs: [BrowserTab] = []
                for url in sites {
                    let started = ContinuousClock.now
                    let tab = store.openTab(url)
                    tabs.append(tab)
                    try? await Task.sleep(for: .seconds(1))
                    for _ in 0..<190 where tab.isLoading {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    DebugHooks.log("QA memory load: \(url.host() ?? "") \(started.duration(to: .now))")
                }
                DebugHooks.log("QA memory autoconsent: \(AutoconsentBridge.framesServed) frames (\(AutoconsentBridge.mainFramesServed) main), \(AutoconsentBridge.bytesServed) B of rules, \(AutoconsentBridge.evaluations) page checks so far")
                await step("round \(round) loaded")
                if environment["KAIZU_HIBERNATE"] != nil {
                    await store.app.hibernateIdleTabs(olderThan: 0)
                    for tab in tabs where tab.isLoaded {
                        let reason = store.isShowing(tab) ? "on screen" : await tab.isBusy ? "playing" : "unknown"
                        DebugHooks.log("QA memory kept: \(tab.url?.host() ?? "") \(reason)")
                    }
                    await step("round \(round) hibernated")
                }
                tabs.forEach(store.close)
                await step("round \(round) closed")
            }
            await step("done")
            NSApp.terminate(nil)
        }
    }

    static func qaStress(_ store: BrowserStore) {
        let app = store.app
        let count = ProcessInfo.processInfo.environment["KAIZU_TABS"].flatMap(Int.init) ?? 2_000
        func log(_ text: String) {
            DebugHooks.log("QA stress: \(text)")
        }
        func time(_ label: String, times: Int = 1, _ body: () -> Void) {
            let start = ContinuousClock.now
            for _ in 0..<times { body() }
            let total = (ContinuousClock.now - start) / times
            log("\(label): \(Double(total.components.attoseconds) / 1e15 + Double(total.components.seconds) * 1000) ms")
        }
        var process = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var query = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        sysctl(&query, 4, &process, &size, nil, 0)
        let started = process.kp_proc.p_starttime
        let launch = Date().timeIntervalSince1970 - (Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000)
        log("launch: \(Int(launch * 1000)) ms with \(store.activeSpace.allTabs.count) tabs")
        Task {
            let space = store.activeSpace
            if space.pinned.tabs.count < count {
                let pages = (0..<count).map { BrowsingData.Bookmark.page(title: "Page \($0) - Example", url: URL(string: "https://example.com/\($0)")!) }
                let data = BrowsingData(bookmarks: pages)
                let bookmarks = data.bookmarkFolder(named: "Stress", skipping: [])
                await app.importBrowsingData([], bookmarks: bookmarks, into: space)
                log("added \(space.pinned.tabs.count) pinned tabs")
            }
            let first = store.openTab(URL(string: "about:blank"))
            let second = store.openTab(URL(string: "about:blank"))
            try? await Task.sleep(for: .seconds(1))
            log("tabs in space: \(space.allTabs.count)")
            time("selectedTab", times: 1000) { _ = store.selectedTab }
            time("allTabs", times: 100) { _ = space.allTabs }
            time("backgroundMediaTab", times: 100) { _ = store.backgroundMediaTab }
            time("isShowing", times: 1000) { _ = store.isShowing(first) }
            time("tab switch (model only)", times: 200) { store.select(first); store.select(second) }
            time("save on the main thread") { app.save(inBackground: true) }
            time("updateSpotlight unchanged") { app.updateSpotlight() }
            if let folder = space.pinned.folders.first {
                time("open folder") {
                    store.toggle(folder)
                    store.window?.contentView?.layoutSubtreeIfNeeded()
                    store.window?.displayIfNeeded()
                }
                try? await Task.sleep(for: .seconds(1))
                time("tab switch, folder open") {
                    store.select(first)
                    store.window?.contentView?.layoutSubtreeIfNeeded()
                    store.window?.displayIfNeeded()
                }
                time("close folder") {
                    store.toggle(folder)
                    store.window?.contentView?.layoutSubtreeIfNeeded()
                    store.window?.displayIfNeeded()
                }
            }
            second.title = "Changed"
            time("saveTabStates") { app.saveTabStates() }
            try? await Task.sleep(for: .seconds(2))
            NSApp.terminate(nil)
        }
    }

    static func qaSites(_ store: BrowserStore) {
        let environment = ProcessInfo.processInfo.environment
        guard let list = environment["KAIZU_SITES"], let text = try? String(contentsOfFile: list, encoding: .utf8) else { return }
        let probe = """
            JSON.stringify({text: document.body ? document.body.innerText.trim().length : -1,
              nodes: document.querySelectorAll('*').length, images: document.images.length,
              height: document.documentElement.scrollHeight,
              consent: (window.kaizuAutoconsent?.messages ?? []).filter(m => m.type != 'eval').map(m => m.type + (m.cmp ? ':' + m.cmp : '') + (m.result !== undefined ? '=' + m.result : '')).slice(-6),
              oneTap: !!document.querySelector('iframe[src*="accounts.google.com/gsi/iframe/select"]') && getComputedStyle(document.querySelector('iframe[src*="accounts.google.com/gsi/iframe/select"]')).display != 'none'})
            """
        let settling = environment["KAIZU_SITE_WAIT"].flatMap(Double.init) ?? 2.5
        Task {
            for line in text.split(separator: "\n") {
                guard let url = URL(string: String(line)) else { continue }
                let tab = store.openTab(url)
                let start = ContinuousClock.now
                try? await Task.sleep(for: .seconds(1))
                while tab.isLoading, ContinuousClock.now - start < .seconds(15) {
                    try? await Task.sleep(for: .milliseconds(250))
                }
                let loaded = (ContinuousClock.now - start).components.seconds
                try? await Task.sleep(for: .seconds(settling))
                // Reads the page's DOM and what autoconsent did, from its world.
                let result = (try? await tab.webView.evaluateJavaScript(probe, contentWorld: AutoconsentBridge.world)) as? String ?? "{}"
                let name = url.host() ?? "site"
                DebugHooks.log("QA site \(name) | \(tab.url?.host() ?? "none") | \(loaded)s\(tab.isLoading ? " still loading" : "") | \(result) | \(tab.title.prefix(50))")
                if let folder = environment["KAIZU_SHOTS"], let image = await tab.screenshot(of: nil), let data = image.tiffRepresentation {
                    let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
                    try? png?.write(to: URL(fileURLWithPath: folder).appending(path: "\(name).png"))
                }
                store.close(tab)
            }
            NSApp.terminate(nil)
        }
    }
}
#endif
