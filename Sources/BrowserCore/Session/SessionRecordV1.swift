import Foundation

/// Version 1 (Oct 2026): a profile *was* a space, its pinned grid became
/// favorites and its tab list became today's tabs.
struct SessionRecordV1: Decodable {
    struct Profile: Decodable {
        var id: UUID
        var name: String
        var hue: Double
        var symbol: String
        var selectedTabID: UUID?
        var pinnedTabs: [Tab]
        var tabs: [Tab]
    }

    struct Tab: Decodable {
        var id: UUID
        var title: String
        var url: URL?
        var pinnedURL: URL?
    }

    var activeProfileID: UUID?
    var isSidebarVisible: Bool
    var sidebarWidth: Double
    var profiles: [Profile]

    /// Each v1 profile becomes a profile (same id, so its website data and
    /// logins stay attached) plus one space with the same name and look.
    func upgraded(now: Date) -> SessionRecord {
        func tab(_ tab: Tab) -> TabRecord {
            // Count restored tabs as fresh so the archiver doesn't sweep them at once.
            TabRecord(id: tab.id, title: tab.title, url: tab.url, pinnedURL: tab.pinnedURL, lastActiveAt: now)
        }
        return SessionRecord(
            activeSpaceID: activeProfileID,
            isSidebarVisible: isSidebarVisible,
            sidebarWidth: sidebarWidth,
            profiles: profiles.map { ProfileRecord(id: $0.id, name: $0.name, favorites: $0.pinnedTabs.map(tab)) },
            spaces: profiles.map {
                SpaceRecord(
                    id: $0.id, name: $0.name, symbol: $0.symbol, hue: $0.hue, profileID: $0.id,
                    selectedTabID: $0.selectedTabID, pinned: [], today: $0.tabs.map(tab)
                )
            }
        )
    }
}
