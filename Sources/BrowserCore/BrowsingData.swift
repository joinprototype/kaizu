import Foundation

/// What another browser hands over: pages it has been to, and its bookmarks.
public struct BrowsingData: Equatable, Sendable {
    public struct Visit: Equatable, Sendable {
        public var url: URL
        public var title: String
        public var count: Int
        public var lastVisit: Date

        public init(url: URL, title: String, count: Int, lastVisit: Date) {
            self.url = url
            self.title = title
            self.count = count
            self.lastVisit = lastVisit
        }
    }

    public enum Bookmark: Equatable, Sendable {
        case page(title: String, url: URL)
        case folder(name: String, children: [Bookmark])
    }

    public enum Failure: Error, Equatable {
        case unreadable
    }

    /// The newest pages are plenty for the command bar.
    public static let visitLimit = 50_000
    /// Each one becomes a pinned tab, so there has to be an end somewhere.
    public static let bookmarkLimit = 2_000

    public var visits: [Visit]
    public var bookmarks: [Bookmark]

    public init(visits: [Visit] = [], bookmarks: [Bookmark] = []) {
        self.visits = visits
        self.bookmarks = bookmarks
    }

    public var isEmpty: Bool { visits.isEmpty && bookmarks.isEmpty }

    /// Only pages: a bookmarklet is a script, and `file:` isn't the web.
    static func webURL(_ text: String) -> URL? {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    /// The bookmarks as one closed pinned folder, leaving out addresses in
    /// `known` and repeats. Nil when none of them are new. `count` is how many
    /// it holds, `bookmarkLimit` at most.
    public func bookmarkFolder(named name: String, skipping known: Set<URL>) -> (folder: FolderRecord, count: Int)? {
        var seen = known
        var count = 0
        func records(_ bookmarks: [Bookmark]) -> [SidebarItemRecord] {
            bookmarks.compactMap { bookmark in
                switch bookmark {
                case .page(let title, let url):
                    guard count < Self.bookmarkLimit, seen.insert(url).inserted else { return nil }
                    count += 1
                    return .tab(TabRecord(id: UUID(), title: title, url: url, pinnedURL: url))
                case .folder(let name, let children):
                    let kept = records(children)
                    return kept.isEmpty ? nil : .folder(FolderRecord(id: UUID(), name: name, isExpanded: false, children: kept))
                }
            }
        }
        let children = records(bookmarks)
        return children.isEmpty ? nil : (FolderRecord(id: UUID(), name: name, isExpanded: false, children: children), count)
    }
}
