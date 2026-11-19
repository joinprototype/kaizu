import AppKit
import WebKit

extension BrowserTab {
    /// Your answer about a site's notifications. Private windows don't read
    /// any: every site there is one that hasn't been asked.
    func notificationAnswer(for host: String) -> Bool? {
        profile.isPrivate ? nil : app?.settings.sitePermissions[host]?[SiteNotifications.permission]
    }

    /// The site this tab could hear from in the background, if it's allowed
    /// to notify you. See `AppModel.notifyingTabs`.
    var notifyingHost: String? {
        // The web view knows a new page before `url` catches up.
        guard !isPopupPage, let host = (_webView?.url ?? url)?.host(), notificationAnswer(for: host) == true
        else { return nil }
        return host
    }

    /// A site's answer about notifications, from the page's question or the
    /// site popover. macOS is asked too, the first time one is allowed.
    func setNotifications(_ allowed: Bool?, for host: String) {
        app?.settings.setPermission(SiteNotifications.permission, to: allowed, on: host)
        guard allowed == true else { return }
        Task {
            let macOS = await SiteNotifications.requestDelivery()
            if macOS == false {
                store?.showToast("Turn on notifications for Kaizu in System Settings", symbol: "bell.slash")
            } else if needsRebuildToNotify {
                store?.showToast(
                    "Reload so this site can reach you from the background",
                    symbol: "bell",
                    undo: { self.rebuildToNotify() },
                    actionTitle: "Reload",
                    lasts: .seconds(8)
                )
            } else if macOS == nil {
                store?.showToast("They’ll show on this tab and in the Dock", symbol: "bell")
            }
        }
    }

    /// Marks a notification on the tab until you look at it, unless you
    /// already are. When macOS wouldn't take it, the Dock icon asks instead.
    func noteNotification(deliveredByMacOS delivered: Bool) {
        guard let app, !(NSApp.isActive && app.store(showing: self) != nil) else { return }
        unreadNotifications += 1
        if !delivered {
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    func markNotificationsRead() {
        if unreadNotifications > 0 {
            unreadNotifications = 0
        }
    }

    /// Allowed since its web view was made, or arrived here by a link, so
    /// it would still be paused in the background: WebKit only reads that
    /// setting at creation.
    var needsRebuildToNotify: Bool {
        guard let _webView, notifyingHost != nil else { return false }
        return _webView.configuration.preferences.inactiveSchedulingPolicy != .throttle
    }

    /// Reloads the page in a web view that keeps running, back/forward intact.
    func rebuildToNotify() {
        hibernate()
        webViewRevision += 1
        activate()
    }
}
