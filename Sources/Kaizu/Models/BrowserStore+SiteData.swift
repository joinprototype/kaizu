import AppKit
import WebKit

extension BrowserStore {
    /// Removes the cookies, storage and caches a site left in the tab's
    /// profile, after asking. WebKit keeps them per registrable domain, so
    /// mail.google.com's are google.com's: the question names the domain
    /// that will actually be cleared.
    func clearSiteData(for tab: BrowserTab) {
        guard let url = tab.url, let site = ContentBlocker.site(for: url) else { return }
        let dataStore = tab.profile.dataStore
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        Task {
            let records = await dataStore.dataRecords(ofTypes: types)
            // The site's own domain, or the one it's under.
            let domain = records.map(\.displayName)
                .filter { site == $0 || site.hasSuffix("." + $0) }
                .max { $0.count < $1.count }
            guard let domain else {
                return showToast("\(site) hasn’t stored anything", symbol: "checkmark.circle")
            }
            let alert = NSAlert()
            alert.messageText = "Clear cookies and data for \(domain)?"
            alert.informativeText = domain == site
                ? "You’ll be signed out of \(domain) in this profile. Other sites aren’t affected."
                : "Websites keep data per domain, so this clears all of \(domain), \(site) included: you’ll be signed out of them in this profile. Other sites aren’t affected."
            alert.addButton(withTitle: "Clear").hasDestructiveAction = true
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            await dataStore.removeData(ofTypes: types, for: records.filter { $0.displayName == domain })
            tab.reload()
            showToast("Cleared data for \(domain)", symbol: "trash")
        }
    }
}
