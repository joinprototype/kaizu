import WebEngine
import WebKit

extension BrowserTab: MediaEventsListener {}

extension BrowserTab: SiteNotificationsHost {
    var isInPrivateWindow: Bool { profile.isPrivate }

    func notificationDestination(page: String, url: URL?) -> [String: String] {
        SiteNotificationDestination(tab: self, page: page, url: url).userInfo
    }
}

extension BrowserTab: HiddenItemsHost {
    /// Counts only while its window is picking on this tab, for what it's
    /// picking for, on the page the tab is on (not one it's just leaving),
    /// and never in a private window.
    func picked(_ selector: String, text: String, for purpose: HiddenItems.Purpose, on host: String) {
        guard !profile.isPrivate, let store, store.hidingItemsTabID == id,
              purpose == store.pickingPurpose, host == url?.host()
        else { return }
        switch purpose {
        case .hide: store.settings.hide(selector, on: url)
        case .watch: store.watchPicked(selector, text: text, on: self)
        }
    }
}
