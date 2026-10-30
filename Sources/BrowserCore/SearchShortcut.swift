import Foundation

/// Keyword searches, Raycast-quicklink style: "yt lofi" searches YouTube.
public struct SearchShortcut: Codable, Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var keyword: String
    public var name: String
    /// `%s` is replaced by the percent-encoded query.
    public var template: String

    public init(keyword: String, name: String, template: String) {
        self.keyword = keyword
        self.name = name
        self.template = template
    }

    /// Same keyword, name and template; the id only tells rows apart.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        (lhs.keyword, lhs.name, lhs.template) == (rhs.keyword, rhs.name, rhs.template)
    }

    public static let builtIn: [SearchShortcut] = [
        SearchShortcut(keyword: "yt", name: "YouTube", template: "https://www.youtube.com/results?search_query=%s"),
        SearchShortcut(keyword: "gh", name: "GitHub", template: "https://github.com/search?q=%s"),
        SearchShortcut(keyword: "w", name: "Wikipedia", template: "https://en.wikipedia.org/w/index.php?search=%s"),
        SearchShortcut(keyword: "maps", name: "Apple Maps", template: "https://maps.apple.com/?q=%s"),
        SearchShortcut(keyword: "amz", name: "Amazon", template: "https://www.amazon.com/s?k=%s"),
        SearchShortcut(keyword: "r", name: "Reddit", template: "https://www.reddit.com/search/?q=%s"),
        SearchShortcut(keyword: "x", name: "X", template: "https://x.com/search?q=%s"),
        SearchShortcut(keyword: "img", name: "Google Images", template: "https://www.google.com/search?tbm=isch&q=%s"),
        SearchShortcut(keyword: "so", name: "Stack Overflow", template: "https://stackoverflow.com/search?q=%s"),
        SearchShortcut(keyword: "npm", name: "npm", template: "https://www.npmjs.com/search?q=%s"),
    ]

    /// Splits "yt lofi beats" into the YouTube shortcut and "lofi beats".
    public static func match(_ text: String, in shortcuts: [SearchShortcut] = builtIn) -> (shortcut: SearchShortcut, query: String)? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
        guard parts.count == 2,
              let shortcut = shortcuts.first(where: {
                  $0.keyword.trimmingCharacters(in: .whitespaces).lowercased() == parts[0].lowercased() && $0.template.contains("%s")
              })
        else { return nil }
        let query = parts[1].trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? nil : (shortcut, query)
    }

    public func url(for query: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        let filled = template.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%s", with: encoded)
        // A template typed without a scheme ("site.com/search?q=%s") gets https.
        return URL(string: filled.contains("://") ? filled : "https://" + filled)
    }
}
