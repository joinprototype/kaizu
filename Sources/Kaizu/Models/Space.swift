import BrowserCore
import Foundation

/// What the sidebar shows: a named, themed set of pinned items and today's
/// tabs, backed by one profile (Arc's Spaces).
@MainActor @Observable
final class Space: Identifiable {
    static let symbols = [
        "person.fill", "briefcase.fill", "house.fill", "graduationcap.fill",
        "gamecontroller.fill", "sparkles", "leaf.fill", "flame.fill",
        "star.fill", "heart.fill", "bolt.fill", "globe.americas.fill",
    ]

    let id: UUID
    let profile: Profile
    var name: String
    var symbol: String
    var hue: Double
    var pinned: [SidebarItem] = []
    var today: [BrowserTab] = []
    var selectedTabID: UUID?
    /// Tabs shown side by side (2–4); see BrowserStore+Split.
    var split: [UUID] = [] {
        didSet { if split != oldValue { splitWidths = [] } }
    }
    /// Each split pane's share of the width, set by dragging the dividers;
    /// reset whenever the panes change. Ignored (equal shares) whenever it
    /// doesn't match the pane count.
    var splitWidths: [Double] = []
    /// Light or dark for this space whatever the system uses (Arc does this);
    /// pages follow it too.
    var appearance = Appearance.auto

    enum Appearance: String, CaseIterable {
        case auto, light, dark

        var title: String { rawValue.capitalized }
    }

    init(id: UUID = UUID(), profile: Profile, name: String, symbol: String, hue: Double) {
        self.id = id
        self.profile = profile
        self.name = name
        self.symbol = symbol
        self.hue = hue
    }

    var theme: Theme { Theme.forHue(hue) }

    /// Every tab reachable from this space's sidebar, in sidebar order.
    var allTabs: [BrowserTab] { profile.favorites + pinned.tabs + today }

    /// Tabs the user can currently see (skips collapsed folders); for ⌘1–9 and ⌃Tab.
    var visibleTabs: [BrowserTab] { profile.favorites + pinned.visibleTabs + today }

    /// The split's tabs that still exist, in order; empty unless at least two do.
    var splitTabs: [BrowserTab] {
        let tabs = split.compactMap { id in allTabs.first { $0.id == id } }
        return tabs.count > 1 ? tabs : []
    }

    var selectedTab: BrowserTab? {
        guard let selectedTabID else { return nil }
        return allTabs.first { $0.id == selectedTabID }
    }

    var record: SpaceRecord {
        SpaceRecord(
            id: id, name: name, symbol: symbol, hue: hue, profileID: profile.id,
            selectedTabID: selectedTabID, pinned: pinned.map(\.record), today: today.map(\.record),
            split: split.isEmpty ? nil : split,
            splitWidths: splitWidths.isEmpty ? nil : splitWidths,
            appearance: appearance == .auto ? nil : appearance.rawValue
        )
    }
}
