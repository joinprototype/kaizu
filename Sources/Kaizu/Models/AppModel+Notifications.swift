import AppKit

/// Stored by macOS with the notification, so a click can arrive after a restart.
struct SiteNotificationDestination: Sendable {
    let tabID: UUID?
    let profileID: UUID?
    let spaceID: UUID?
    let page: String
    let url: URL?

    @MainActor
    init(tab: BrowserTab, page: String, url: URL?) {
        tabID = tab.id
        profileID = tab.profile.id
        spaceID = (tab.store?.space(containing: tab) ?? tab.store?.space(on: tab.profile))?.id
        self.page = page
        self.url = url
    }

    init(userInfo: [AnyHashable: Any]) {
        tabID = (userInfo["tab"] as? String).flatMap(UUID.init(uuidString:))
        profileID = (userInfo["profile"] as? String).flatMap(UUID.init(uuidString:))
        spaceID = (userInfo["space"] as? String).flatMap(UUID.init(uuidString:))
        page = userInfo["page"] as? String ?? ""
        url = (userInfo["url"] as? String).flatMap(URL.init(string:))
    }

    var userInfo: [String: String] {
        ["tab": tabID?.uuidString, "profile": profileID?.uuidString, "space": spaceID?.uuidString,
         "page": page, "url": url?.absoluteString].compactMapValues { $0 }
    }
}

extension AppModel {
    func openNotification(_ destination: SiteNotificationDestination) {
        let candidates = spaces.filter { destination.profileID == nil || $0.profile.id == destination.profileID }
        let liveSpace = destination.tabID.flatMap { id in candidates.first { $0.tab(id: id) != nil } }
        let liveTab = destination.tabID.flatMap { liveSpace?.tab(id: $0) }
        let window: BrowserStore
        if let tab = liveTab, tab.url == destination.url, let liveSpace {
            window = store(showing: tab) ?? notificationWindow(for: liveSpace)
            let owner = window.activeSpace.tab(id: tab.id) === tab ? window.activeSpace : liveSpace
            window.select(tab, in: owner)
            SiteNotifications.fireClick(on: tab, notification: destination.page)
        } else {
            guard let url = destination.url, url.scheme == "https", url.host() != nil else { return }
            // Older notifications carried only a tab ID and URL. The closed-tab
            // list and archive can still identify their space.
            let savedID = destination.spaceID ?? destination.tabID.flatMap { id in
                closedTabs.last { $0.record.id == id }?.spaceID ?? archive.first { $0.id == id }?.spaceID
            }
            let saved = candidates.first { $0.id == savedID }
            let knownProfile = destination.profileID != nil || profiles.count == 1
            let fallback = candidates.first { $0 === regularFront.activeSpace } ?? candidates.first
            guard let space = saved ?? liveSpace ?? (knownProfile ? fallback : nil) else { return }
            window = notificationWindow(for: space)
            window.openTab(url, in: space)
        }
        front = window
        showFront()
        NSApp.activate()
    }

    private func notificationWindow(for space: Space) -> BrowserStore {
        if regularFront.activeSpace === space { return regularFront }
        return stores.first { $0.activeSpace === space } ?? regularFront
    }
}
