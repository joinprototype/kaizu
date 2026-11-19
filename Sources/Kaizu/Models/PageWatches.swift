import BrowserCore
import Foundation

/// A part of a page you asked to hear about: a price, a stock label, a
/// score. Kaizu loads the page now and then and compares the part's text.
nonisolated struct WatchedPart: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let selector: String
    /// The page's title when you picked it.
    var title: String
    let profileID: UUID
    /// What the part said at the last check that found it.
    var text: String
    /// What it said before its last change.
    var previous: String?
    var checkedAt: Date?
    var changedAt: Date?
    /// Changed since you last opened the page.
    var isUnseen = false
    /// Checks in a row that couldn't find it on the page.
    var misses = 0

    /// Shown as "can't find it" after this many misses: one can be a slow
    /// load or a sign-in wall that passes.
    static let missesToGiveUp = 3

    var host: String { url.displayHost }
    var isLost: Bool { misses >= Self.missesToGiveUp }
}

/// The parts you watch, kept in Kaizu's own preferences.
@Observable
final class PageWatches {
    static let maximum = 50
    /// Text kept per part: a price or a label, not a page.
    nonisolated static let maximumText = 300
    private static let key = "watchedParts"

    private(set) var parts: [WatchedPart] {
        didSet {
            save()
            if unseenCount != oldValue.count(where: \.isUnseen) { onUnseenChange?() }
        }
    }
    /// The Dock's count follows the changes you haven't seen.
    @ObservationIgnored var onUnseenChange: (() -> Void)?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = AppDefaults.shared) {
        self.defaults = defaults
        parts = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([WatchedPart].self, from: $0) } ?? []
    }

    var unseenCount: Int { parts.count { $0.isUnseen } }

    /// Whitespace runs become one space; long text is cut.
    nonisolated static func normalized(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(words.prefix(maximumText))
    }

    /// Nil when there are already as many as Kaizu keeps, or the part says
    /// nothing to compare.
    @discardableResult
    func add(url: URL, selector: String, text: String, title: String, profileID: UUID) -> WatchedPart? {
        let text = Self.normalized(text)
        guard parts.count < Self.maximum, !text.isEmpty, !selector.isEmpty else { return nil }
        if let index = parts.firstIndex(where: { $0.url == url && $0.selector == selector && $0.profileID == profileID }) {
            parts[index].text = text
            parts[index].misses = 0
            return parts[index]
        }
        let part = WatchedPart(id: UUID(), url: url, selector: selector, title: title, profileID: profileID,
                               text: text, checkedAt: Date())
        parts.append(part)
        return part
    }

    func remove(_ id: UUID) {
        parts.removeAll { $0.id == id }
    }

    /// A deleted profile's parts go with it.
    func removeAll(profile id: UUID) {
        parts.removeAll { $0.profileID == id }
    }

    /// The result of a check: the part's text, or nil when it wasn't on the
    /// page. Returns the part when its text changed.
    @discardableResult
    func record(_ id: UUID, found: String?, at date: Date = Date()) -> WatchedPart? {
        guard let index = parts.firstIndex(where: { $0.id == id }) else { return nil }
        var part = parts[index]
        part.checkedAt = date
        let text = found.map(Self.normalized) ?? ""
        guard !text.isEmpty else {
            part.misses += 1
            parts[index] = part
            return nil
        }
        part.misses = 0
        let changed = text != part.text
        if changed {
            part.previous = part.text
            part.text = text
            part.changedAt = date
            part.isUnseen = true
        }
        parts[index] = part
        return changed ? part : nil
    }

    /// You've opened the page: its changes are seen. Goes by host and path,
    /// as a page often adds or changes its query (locale, session) as it loads.
    func markSeen(_ url: URL?) {
        guard let url else { return }
        let page = Self.page(url)
        guard parts.contains(where: { $0.isUnseen && Self.page($0.url) == page }) else { return }
        for index in parts.indices where Self.page(parts[index].url) == page {
            parts[index].isUnseen = false
        }
    }

    func markSeen(_ id: UUID) {
        guard let index = parts.firstIndex(where: { $0.id == id }), parts[index].isUnseen else { return }
        parts[index].isUnseen = false
    }

    nonisolated static func page(_ url: URL) -> String {
        let host = (url.host() ?? "").lowercased()
        let path = url.path(percentEncoded: true)
        return (host.hasPrefix("www.") ? String(host.dropFirst(4)) : host) + (path.hasSuffix("/") ? String(path.dropLast()) : path)
    }

    /// The ones to check now, oldest check first.
    func due(every interval: TimeInterval, now: Date = Date()) -> [WatchedPart] {
        parts.filter { ($0.checkedAt ?? .distantPast) <= now.addingTimeInterval(-interval) }
            .sorted { ($0.checkedAt ?? .distantPast) < ($1.checkedAt ?? .distantPast) }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(parts), forKey: Self.key)
    }
}
