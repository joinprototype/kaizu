import AppKit
import BrowserCore

extension BrowserStore {
    func toggleContentBlocking() {
        contentBlocker.setEnabled(!contentBlocker.isEnabled)
        showToast(contentBlocker.isEnabled ? "Blocking ads & trackers" : "Ad & tracker blocking off")
        selectedTab?.reload()
    }

    /// `tab` defaults to the selected tab; the menu passes the key window's.
    func toggleBlockingOnCurrentSite(_ tab: BrowserTab? = nil) {
        guard let tab = tab ?? selectedTab, let url = tab.url, let site = ContentBlocker.site(for: url) else { return }
        if contentBlocker.togglePause(on: url, temporarily: tab.profile.isPrivate) {
            // Pausing usually means the page broke: the best moment to ask.
            showToast("Blocking paused on \(site)", undo: { [weak self] in self?.reportBrokenSite(tab) }, actionTitle: "Report…")
        } else {
            showToast("Blocking back on for \(site)")
        }
        tab.reload()
    }

    /// Off a website there's no site to report, so a plain bug report instead.
    func reportBrokenSite(_ tab: BrowserTab? = nil) {
        guard let tab = tab ?? commandTab ?? selectedTab, let url = tab.url, BrokenSiteReport.site(of: url) != nil else {
            UtilityWindows.showBugReport(app: app)
            return
        }
        UtilityWindows.showBrokenSiteReport(tab: tab, url: url, app: app)
    }

    func toggleCookieRejection() {
        contentBlocker.setCookieRejectionEnabled(!contentBlocker.isCookieRejectionEnabled)
        showToast(contentBlocker.isCookieRejectionEnabled ? "Rejecting cookie pop-ups" : "Cookie pop-up rejection off")
        selectedTab?.reload()
    }

    func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear all browsing history?"
        alert.informativeText = "Visited pages, and what the command bar learned you pick, are forgotten in every profile. Open tabs, favorites and the archive stay."
        alert.addButton(withTitle: "Clear History").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await history?.removeAll() }
        app.forgetChoices()
        showToast("History cleared")
    }

    #if DEBUG
    /// What autoconsent did on the current page (main frame only).
    func showCookiePopupResult() {
        guard let tab = selectedTab, tab.isLoaded else { return }
        let script = """
            JSON.stringify((window.autoconsentStandalone?.messages ?? [])
              .filter(m => ['cmpDetected', 'popupFound', 'optOutResult', 'autoconsentDone', 'autoconsentError'].includes(m.type))
              .map(m => m.type + (m.cmp ? ': ' + m.cmp : '') + (m.result !== undefined ? ' = ' + m.result : '')))
            """
        Task {
            let result = (try? await tab.webView.evaluateJavaScript(script)) as? String
            showToast(result.map { $0 == "[]" ? "No cookie pop-up handled on this page" : $0 } ?? "autoconsent not running")
        }
    }
    #endif
}
