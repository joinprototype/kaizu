import Foundation

/// What Kaizu can use from Arc's `StorableSidebar.json`. Arc never documented
/// the format (see docs/research/arc-sidebar-format.md), so anything unexpected
/// is skipped, never fatal.
public struct ArcSidebar: Equatable, Sendable {
    public struct Tab: Equatable, Sendable {
        public var title: String
        public var url: URL
    }

    public indirect enum Item: Equatable, Sendable {
        case tab(Tab)
        case folder(name: String, children: [Item])
    }

    public struct Space: Equatable, Sendable {
        public var name: String
        /// `ArcSidebar.defaultProfile`, or the Arc profile's folder name.
        public var profile: String
        /// Arc's color for the space, when it has one.
        public var hue: Double?
        public var pinned: [Item]
        public var today: [Tab]
    }

    public static let defaultProfile = "default"

    public var spaces: [Space]
    /// Favorites belong to an Arc profile, not a space.
    public var favorites: [String: [Tab]]
    /// Easels, notes, live folders, and pages Kaizu can't open.
    public var skipped: Int

    /// Where Arc keeps it. Kaizu only ever reads this file.
    public static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Arc/StorableSidebar.json")
    }
}

public enum ArcSidebarError: Error, Equatable {
    case unreadable
}

extension [ArcSidebar.Item] {
    /// All tabs, depth-first in sidebar order.
    public var tabs: [ArcSidebar.Tab] {
        flatMap { item -> [ArcSidebar.Tab] in
            switch item {
            case .tab(let tab): [tab]
            case .folder(_, let children): children.tabs
            }
        }
    }
}

// MARK: - Parsing

extension ArcSidebar {
    private typealias JSON = [String: Any]

    public static func load(from url: URL = fileURL) throws -> ArcSidebar {
        try parse(Data(contentsOf: url))
    }

    public static func parse(_ data: Data) throws -> ArcSidebar {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? JSON,
              let containers = (root["sidebar"] as? JSON)?["containers"] as? [Any],
              let main = mainContainer(in: containers)
        else { throw ArcSidebarError.unreadable }

        let items = objects(main["items"])
        var tree = ItemTree(items)
        let spaces = objects(main["spaces"]).enumerated().map { index, object in
            space(from: object, position: index + 1, tree: &tree)
        }
        var favorites: [String: [Tab]] = [:]
        for item in items {
            let container = ((item["data"] as? JSON)?["itemContainer"] as? JSON)?["containerType"] as? JSON
            guard let id = item["id"] as? String, let topApps = container?["topApps"] as? JSON else { continue }
            // One profile can have a container per Mac: put them together.
            let profile = profileName(topApps["_0"])
            for tab in tree.children(of: id).tabs where !(favorites[profile] ?? []).contains(where: { $0.url == tab.url }) {
                favorites[profile, default: []].append(tab)
            }
        }
        return ArcSidebar(spaces: spaces, favorites: favorites, skipped: tree.skipped)
    }

    /// The window's own sidebar is the value after the `global` key. Little
    /// Arc and standalone windows keep separate containers in the same list.
    private static func mainContainer(in containers: [Any]) -> JSON? {
        for (index, key) in containers.enumerated() where (key as? JSON)?["global"] != nil && index + 1 < containers.count {
            if let value = containers[index + 1] as? JSON { return value }
        }
        for (index, element) in containers.enumerated() {
            guard let value = element as? JSON, value["spaces"] != nil, value["items"] != nil else { continue }
            if index > 0, (containers[index - 1] as? JSON)?["littleBrowser"] != nil { continue }
            return value
        }
        return nil
    }

    /// Arc writes dictionaries as flat `key, value` arrays; each value also
    /// carries its own id, so the objects alone are enough.
    private static func objects(_ value: Any?) -> [JSON] {
        if let array = value as? [Any] { return array.compactMap { $0 as? JSON } }
        if let dictionary = value as? JSON { return dictionary.values.compactMap { $0 as? JSON } }
        return []
    }

    private static func space(from object: JSON, position: Int, tree: inout ItemTree) -> Space {
        let id = object["id"] as? String
        let (pinned, today) = sectionIDs(of: object)
        return Space(
            name: clean(object["title"]) ?? (id == "thebrowser.company.defaultPersonalSpaceID" ? "Personal" : "Space \(position)"),
            profile: profileName(object["profile"]),
            hue: hue(of: object),
            pinned: pinned.map { tree.children(of: $0) } ?? [],
            today: today.map { tree.children(of: $0).tabs } ?? []
        )
    }

    /// By marker, never by position: both orders occur. Older files have only
    /// one of the two lists.
    private static func sectionIDs(of space: JSON) -> (pinned: String?, today: String?) {
        var pinned: String?
        var today: String?
        for key in ["containerIDs", "newContainerIDs"] {
            guard let pairs = space[key] as? [Any], pairs.count > 1 else { continue }
            for index in stride(from: 0, to: pairs.count - 1, by: 2) {
                guard let id = pairs[index + 1] as? String else { continue }
                let marker = pairs[index] as? String ?? (pairs[index] as? JSON)?.keys.first
                if marker == "pinned", pinned == nil { pinned = id }
                if marker == "unpinned", today == nil { today = id }
            }
        }
        return (pinned, today)
    }

    private static func profileName(_ tag: Any?) -> String {
        let custom = ((tag as? JSON)?["custom"] as? JSON)?["_0"] as? JSON
        guard let name = custom?["directoryBasename"] as? String, !name.isEmpty else { return defaultProfile }
        return name
    }

    private static func hue(of space: JSON) -> Double? {
        let theme = (space["customInfo"] as? JSON)?["windowTheme"] as? JSON
        guard let color = (theme?["primaryColorPalette"] as? JSON)?["midTone"] as? JSON,
              let red = color["red"] as? Double, let green = color["green"] as? Double, let blue = color["blue"] as? Double
        else { return nil }
        return hue(red: red, green: green, blue: blue)
    }

    /// 0–1, or nil for greys, which have no hue to speak of. Arc's colors are
    /// extended sRGB, so components can fall outside 0–1.
    static func hue(red: Double, green: Double, blue: Double) -> Double? {
        let (r, g, b) = (min(max(red, 0), 1), min(max(green, 0), 1), min(max(blue, 0), 1))
        let high = max(r, g, b)
        let range = high - min(r, g, b)
        guard range > 0.08 else { return nil }
        let sector = high == r ? (g - b) / range : high == g ? (b - r) / range + 2 : (r - g) / range + 4
        return (sector / 6 + 1).truncatingRemainder(dividingBy: 1)
    }

    /// Trimmed, including the invisible characters some sites put in titles;
    /// nil when nothing is left.
    private static func clean(_ text: Any?) -> String? {
        let cleaned = (text as? String)?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return cleaned?.isEmpty == false ? cleaned : nil
    }

    /// Items sit in one flat table; `childrenIds` gives the order. An item
    /// that only names its parent still belongs under it.
    private struct ItemTree {
        private let items: [String: JSON]
        private var orphans: [String: [String]] = [:]
        private var visited: Set<String> = []
        private(set) var skipped = 0

        init(_ objects: [JSON]) {
            items = Dictionary(objects.compactMap { object in (object["id"] as? String).map { ($0, object) } }) { _, last in last }
            for object in objects {
                guard let id = object["id"] as? String, let parent = object["parentID"] as? String, let owner = items[parent] else { continue }
                if !(owner["childrenIds"] as? [String] ?? []).contains(id) {
                    orphans[parent, default: []].append(id)
                }
            }
        }

        mutating func children(of id: String, depth: Int = 0) -> [Item] {
            ((items[id]?["childrenIds"] as? [String] ?? []) + (orphans[id] ?? [])).flatMap { convert($0, depth: depth + 1) }
        }

        /// A guard against cycles too: each item is used once, and nesting
        /// stops well past what anyone builds by hand.
        private mutating func convert(_ id: String, depth: Int) -> [Item] {
            guard depth < 32, visited.insert(id).inserted, let item = items[id], let data = item["data"] as? JSON else { return [] }
            if let tab = data["tab"] as? JSON {
                guard let converted = ItemTree.tab(from: tab, item: item) else {
                    skipped += 1
                    return []
                }
                return [.tab(converted)]
            }
            if let list = data["list"] {
                // Live folders fill themselves from a service Kaizu doesn't talk to.
                if (list as? JSON)?["automaticLiveFolderData"] != nil {
                    skipped += 1
                    return []
                }
                let children = children(of: id, depth: depth)
                return children.isEmpty ? [] : [.folder(name: clean(item["title"]) ?? "Untitled Folder", children: children)]
            }
            // A split view's tabs stay in place, one after the other.
            if data["splitView"] != nil || data["itemContainer"] != nil {
                return children(of: id, depth: depth)
            }
            skipped += 1
            return []
        }

        private static func tab(from tab: JSON, item: JSON) -> Tab? {
            guard let address = tab["savedURL"] as? String, let url = URL(string: address),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  let host = url.host(), !host.isEmpty
            else { return nil }
            return Tab(title: clean(item["title"]) ?? clean(tab["savedTitle"]) ?? host, url: url)
        }
    }
}
