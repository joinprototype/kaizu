#if DEBUG
import AppKit
import BrowserCore
import WebEngine
import WebKit

extension DebugHooks {
    /// `open`: KAIZU_URL in a new tab, then logs whether the page shows.
    /// KAIZU_INSTALL=1 on a store page installs its extension without asking.
    static func qaOpen(_ store: BrowserStore) {
        if let url = ProcessInfo.processInfo.environment["KAIZU_URL"].flatMap(URL.init(string:)) {
            store.openTab(url)
        }
        Task {
            try? await Task.sleep(for: .seconds(6))
            let shown = store.window?.contentView.flatMap(webContainer(in:)) != nil
            log("QA selected \(String(describing: store.selectedTab?.url)) page shown \(shown)")
            if ProcessInfo.processInfo.environment["KAIZU_INSTALL"] != nil,
               let listing = ExtensionGallery.listing(for: store.selectedTab?.url) {
                await store.extensions.install(listing, askFirst: false)
                let names = store.extensions.installed.map(\.name)
                log("QA installed \(names) listed \(store.extensions.isInstalled(listing))")
            }
        }
    }

    /// `reader`: KAIZU_URL opens a throwaway tab for it, closed again after 12 s.
    static func qaReader(_ store: BrowserStore) {
        let tab = ProcessInfo.processInfo.environment["KAIZU_URL"].flatMap(URL.init(string:)).map { store.openTab($0) }
        Task {
            try? await Task.sleep(for: .seconds(4))
            store.toggleReader()
            try? await Task.sleep(for: .seconds(8))
            if let tab { store.close(tab) }
        }
    }

    /// `capture`: opens a page and starts ⇧⌘2 on it. Opens a tab: use with KAIZU_SUPPORT.
    static func qaCapture(_ store: BrowserStore) {
        let tab = store.openTab(URL(string: "https://www.swift.org/about/"))
        Task {
            try? await Task.sleep(for: .seconds(3))
            store.beginCapture(of: tab)
        }
    }

    /// `hide`: clicks example.com's paragraph through the picking shield (by
    /// script; see HiddenItems.isReal), reloads, and logs what was
    /// remembered and whether it stays hidden.
    static func qaHide(_ store: BrowserStore) {
        let tab = store.openTab(URL(string: "https://example.com/"))
        Task {
            // A fresh profile can take longer than a few seconds for its first page.
            for _ in 0..<150 where tab.isLoading || tab.title.isEmpty {
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .seconds(1))
            store.beginHidingItems(on: tab)
            try? await Task.sleep(for: .seconds(1))
            _ = try? await tab.webView.evaluateJavaScript("""
                window.__kaizuQA = true;
                const r = document.querySelector("p").getBoundingClientRect();
                const [x, y] = [r.left + r.width / 2, r.top + r.height / 2];
                const shield = document.elementFromPoint(x, y);
                for (const type of ["mousemove", "click"]) {
                    shield.dispatchEvent(new MouseEvent(type, { clientX: x, clientY: y, bubbles: true, cancelable: true }));
                }
                0
                """, in: nil, contentWorld: HiddenItems.world)
            try? await Task.sleep(for: .seconds(1))
            store.endHidingItems()
            let remembered = store.settings.hiddenItems(on: tab.url)
            tab.reload()
            try? await Task.sleep(for: .seconds(4))
            let display = try? await tab.webView.evaluateJavaScript("getComputedStyle(document.querySelector('p')).display")
            log("QA hide: remembered \(remembered), after reload display \(String(describing: display))")
            store.settings.showHiddenItems(on: tab.url)
        }
    }

    /// `brokensite`: see the list in DebugHooks.swift.
    static func qaBrokenSite(_ store: BrowserStore) {
        guard let url = ProcessInfo.processInfo.environment["KAIZU_URL"].flatMap(URL.init(string:)) else { return }
        let tab = store.openTab(url)
        Task {
            try? await Task.sleep(for: .seconds(4))
            store.toggleBlockingOnCurrentSite(tab)
            store.toast?.undo?()
            try? await Task.sleep(for: .seconds(2))
            saveShot(ofWindow: "Report a Broken Site")
            let details = BugReport.siteDetails(for: url, tab: tab, store: store).joined(separator: "; ")
            log("QA broken site: \(details)")
        }
    }

    /// `bugreport`: opens Report a Bug, and also writes a report (as
    /// "Show in Finder" would) and logs where.
    static func qaBugReport(_ store: BrowserStore) {
        UtilityWindows.showBugReport(app: store.app)
        Task {
            try? await Task.sleep(for: .seconds(3))
            let zip = try? await BugReport.write(summary: "QA report", includingDiagnostics: true, store: store)
            log("QA report \(zip?.path ?? "failed")")
        }
    }
}
#endif
