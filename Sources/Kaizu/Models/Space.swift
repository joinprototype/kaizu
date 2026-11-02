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
    /// How the tabs shown together (2–4) sit; see BrowserStore+Split.
    var splitLayout: SplitNode? {
        didSet { split = splitLayout?.panes ?? [] }
    }
    /// Those tabs, top left first. Kept, not worked out: sidebar rows ask on
    /// every render.
    private(set) var split: [UUID] = []
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
        let tabs = split.compactMap(tab(id:))
        return tabs.count > 1 ? tabs : []
    }

    /// What shows when `tab` is selected: the split it's in, or it alone.
    func panes(with tab: BrowserTab) -> [BrowserTab] {
        let split = splitTabs
        return split.contains(tab) ? split : [tab]
    }

    /// How `panes`, from `panes(with:)`, sit: the split without any tab
    /// that's gone, or a lone page.
    func layout(of panes: [BrowserTab]) -> SplitNode {
        splitLayout?.keeping(Set(panes.map(\.id))) ?? .pane(panes[0].id)
    }

    /// A split of one is no split.
    func removeFromSplit(_ id: UUID) {
        splitLayout = splitLayout?.removing(id)
        if splitTabs.isEmpty {
            splitLayout = nil
        }
    }

    func tab(id: UUID) -> BrowserTab? {
        firstTab { $0.id == id }
    }

    /// `allTabs.first`, for what runs on every render: it builds no array.
    func firstTab(where matches: (BrowserTab) -> Bool) -> BrowserTab? {
        today.first(where: matches) ?? profile.favorites.first(where: matches) ?? pinned.firstTab(where: matches)
    }

    /// Where the space's pinned tabs and favorites live, for not adding them twice.
    var pinnedAddresses: Set<URL> {
        Set((pinned.tabs + profile.favorites).compactMap { $0.pinnedURL ?? $0.url })
    }

    /// Without a selection: each window keeps its own.
    var record: SpaceRecord {
        SpaceRecord(
            id: id, name: name, symbol: symbol, hue: hue, profileID: profile.id,
            selectedTabID: nil, pinned: pinned.map(\.record), today: today.map(\.record),
            split: split.isEmpty ? nil : split,
            splitLayout: splitLayout,
            appearance: appearance == .auto ? nil : appearance.rawValue
        )
    }
}
