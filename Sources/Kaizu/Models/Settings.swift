import BrowserCore
import Foundation

/// User preferences, persisted as one JSON value in UserDefaults.
@MainActor @Observable
final class Settings {
    enum ExternalLinks: String, CaseIterable, Codable {
        case littleWindow, currentSpace

        var title: String {
            switch self {
            case .littleWindow: "A little window"
            case .currentSpace: "The current space"
            }
        }
    }

    enum ArchiveInterval: String, CaseIterable, Codable {
        case twelveHours, day, week, never

        var title: String {
            switch self {
            case .twelveHours: "12 hours"
            case .day: "1 day"
            case .week: "7 days"
            case .never: "Never"
            }
        }

        var seconds: TimeInterval? {
            switch self {
            case .twelveHours: 12 * 60 * 60
            case .day: 24 * 60 * 60
            case .week: 7 * 24 * 60 * 60
            case .never: nil
            }
        }
    }

    /// The shortcut that brings up the quick bar from any app. (⌘Space,
    /// ⌃Space, ⌃⌥Space, ⌥⌘Space and ⇧⌘Space are the system's.)
    enum QuickBarKey: String, CaseIterable, Codable {
        case optionSpace, shiftOptionSpace, controlShiftSpace

        var title: String {
            switch self {
            case .optionSpace: "⌥Space"
            case .shiftOptionSpace: "⌥⇧Space"
            case .controlShiftSpace: "⌃⇧Space"
            }
        }
    }

    private struct Snapshot: Codable {
        var searchEngine = SearchEngine.google
        var externalLinks = ExternalLinks.littleWindow
        var linkRoutes: [LinkRoute] = []
        var archiveAfter = ArchiveInterval.twelveHours
        var sitePermissions: [String: [String: Bool]] = [:]
        var siteZoom: [String: Double] = [:]
        var autoPictureInPicture = true
        var searchSuggestions = false
        /// nil while they're the built-in ones, so later releases can add to those.
        var searchShortcuts: [SearchShortcut]?
        var quickBarKey: QuickBarKey?
        var hiddenItems: [String: [String]] = [:]

        init() {}

        /// Missing keys fall back to defaults, so adding a setting never resets the others.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = Snapshot()
            searchEngine = (try? container.decode(SearchEngine.self, forKey: .searchEngine)) ?? defaults.searchEngine
            externalLinks = (try? container.decode(ExternalLinks.self, forKey: .externalLinks)) ?? defaults.externalLinks
            linkRoutes = (try? container.decode([LinkRoute].self, forKey: .linkRoutes)) ?? defaults.linkRoutes
            archiveAfter = (try? container.decode(ArchiveInterval.self, forKey: .archiveAfter)) ?? defaults.archiveAfter
            sitePermissions = (try? container.decode([String: [String: Bool]].self, forKey: .sitePermissions)) ?? defaults.sitePermissions
            siteZoom = (try? container.decode([String: Double].self, forKey: .siteZoom)) ?? defaults.siteZoom
            autoPictureInPicture = (try? container.decode(Bool.self, forKey: .autoPictureInPicture)) ?? defaults.autoPictureInPicture
            searchSuggestions = (try? container.decode(Bool.self, forKey: .searchSuggestions)) ?? defaults.searchSuggestions
            searchShortcuts = try? container.decode([SearchShortcut].self, forKey: .searchShortcuts)
            quickBarKey = try? container.decode(QuickBarKey.self, forKey: .quickBarKey)
            hiddenItems = (try? container.decode([String: [String]].self, forKey: .hiddenItems)) ?? defaults.hiddenItems
        }
    }

    private static let key = "settings"

    /// Switching engines turns suggestions off: agreeing to send typing to
    /// one engine isn't agreeing for another.
    var searchEngine: SearchEngine {
        didSet {
            if searchEngine != oldValue { searchSuggestions = false }
            save()
        }
    }
    var externalLinks: ExternalLinks { didSet { save() } }
    /// Air Traffic Control rules; the first match wins.
    var linkRoutes: [LinkRoute] { didSet { save() } }
    var archiveAfter: ArchiveInterval { didSet { save() } }
    /// Remembered permission answers: host → device ("camera",
    /// "microphone", "location") → allowed.
    var sitePermissions: [String: [String: Bool]] { didSet { save() } }
    /// Page zoom per host, remembered like Safari; 100% isn't stored.
    var siteZoom: [String: Double] { didSet { save() } }
    /// A playing video floats in picture in picture when you switch away
    /// from its tab, and comes back when you return (Arc does this).
    var autoPictureInPicture: Bool { didSet { save() } }
    /// Off by default: it sends what you type in the command bar to the
    /// search engine as you type.
    var searchSuggestions: Bool { didSet { save() } }
    /// Command bar keywords: "yt lofi" searches YouTube.
    var searchShortcuts: [SearchShortcut] { didSet { save() } }
    /// Off (nil) by default: a global shortcut takes the keys from every app.
    var quickBarKey: QuickBarKey? { didSet { save() } }
    /// "Hide Distracting Items": CSS selectors hidden per site.
    var hiddenItems: [String: [String]] { didSet { save() } }

    init() {
        let stored = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } ?? Snapshot()
        searchEngine = stored.searchEngine
        externalLinks = stored.externalLinks
        linkRoutes = stored.linkRoutes
        archiveAfter = stored.archiveAfter
        sitePermissions = stored.sitePermissions
        siteZoom = stored.siteZoom
        autoPictureInPicture = stored.autoPictureInPicture
        searchSuggestions = stored.searchSuggestions
        searchShortcuts = stored.searchShortcuts ?? SearchShortcut.builtIn
        quickBarKey = stored.quickBarKey
        hiddenItems = stored.hiddenItems
    }

    private func save() {
        var snapshot = Snapshot()
        snapshot.searchEngine = searchEngine
        snapshot.externalLinks = externalLinks
        snapshot.linkRoutes = linkRoutes
        snapshot.archiveAfter = archiveAfter
        snapshot.sitePermissions = sitePermissions
        snapshot.siteZoom = siteZoom
        snapshot.autoPictureInPicture = autoPictureInPicture
        snapshot.searchSuggestions = searchSuggestions
        snapshot.searchShortcuts = searchShortcuts == SearchShortcut.builtIn ? nil : searchShortcuts
        snapshot.quickBarKey = quickBarKey
        snapshot.hiddenItems = hiddenItems
        UserDefaults.standard.set(try? JSONEncoder().encode(snapshot), forKey: Self.key)
    }
}

extension Settings {
    func zoom(for url: URL?) -> Double {
        Self.siteKey(for: url).flatMap { siteZoom[$0] } ?? 1
    }

    func setZoom(_ zoom: Double, for url: URL?) {
        guard let key = Self.siteKey(for: url) else { return }
        siteZoom[key] = abs(zoom - 1) < 0.01 ? nil : zoom
    }

    /// Items anchored to an id are hidden across the site; ones found by
    /// position (from the body) only on the page they were picked on, where
    /// the position means the same thing.
    func hiddenItems(on url: URL?) -> [String] {
        guard let site = Self.siteKey(for: url) else { return [] }
        return (hiddenItems[site] ?? []) + (Self.pageKey(for: url).flatMap { hiddenItems[$0] } ?? [])
    }

    func hide(_ selector: String, on url: URL?) {
        let key = selector.hasPrefix("body") ? Self.pageKey(for: url) : Self.siteKey(for: url)
        guard let key, let site = Self.siteKey(for: url), !(hiddenItems[key] ?? []).contains(selector),
              hiddenItems.filter({ $0.key == site || $0.key.hasPrefix(site + "/") }).values.joined().count < HiddenItems.maximumPerSite
        else { return }
        hiddenItems[key, default: []].append(selector)
    }

    /// Everything hidden anywhere on the site comes back.
    func showHiddenItems(on url: URL?) {
        guard let site = Self.siteKey(for: url) else { return }
        hiddenItems = hiddenItems.filter { $0.key != site && !$0.key.hasPrefix(site + "/") }
    }

    private static func pageKey(for url: URL?) -> String? {
        guard let site = siteKey(for: url), let url else { return nil }
        let path = url.path(percentEncoded: true)
        return site + (path.isEmpty ? "/" : path)
    }

    /// The host without "www.", which per-site settings are kept under.
    private static func siteKey(for url: URL?) -> String? {
        guard let host = url?.host()?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
