import Foundation
import SQLite3

/// One profile of a Chromium browser on this Mac. Arc, Chrome and the rest
/// all keep a `History` database and a `Bookmarks` file per profile folder.
/// Only ever read, from a copy: a running browser holds the database locked.
public struct ChromiumProfile: Hashable, Sendable, Identifiable {
    /// Where each keeps its profile folders, under Application Support.
    private static let browsers = [
        ("Arc", "Arc/User Data"),
        ("Chrome", "Google/Chrome"),
        ("Brave", "BraveSoftware/Brave-Browser"),
        ("Edge", "Microsoft Edge"),
        ("Vivaldi", "Vivaldi"),
    ]
    /// Chromium counts in microseconds from 1601.
    private static let epochOffset = 11_644_473_600.0

    public var browser: String
    /// "Chrome", or "Chrome: Work" for a browser with several profiles.
    public var title: String
    public var directory: URL

    public var id: URL { directory }

    public init(browser: String, title: String, directory: URL) {
        self.browser = browser
        self.title = title
        self.directory = directory
    }

    public static func installed(
        in support: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
    ) -> [ChromiumProfile] {
        browsers.flatMap { browser, path in
            let root = support.appending(path: path, directoryHint: .isDirectory)
            let folders = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
            let profiles = folders
                .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
                .filter { FileManager.default.fileExists(atPath: root.appending(path: "\($0)/History").path) }
                .sorted { ($0 == "Default" ? 0 : 1, $0) < ($1 == "Default" ? 0 : 1, $1) }
            let names = profileNames(in: root)
            return profiles.map { folder in
                let name = names[folder] ?? folder
                return ChromiumProfile(
                    browser: browser,
                    title: profiles.count > 1 ? "\(browser): \(name)" : browser,
                    directory: root.appending(path: folder, directoryHint: .isDirectory)
                )
            }
        }
    }

    /// What people called their profiles, from the browser's `Local State`.
    private static func profileNames(in root: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: root.appending(path: "Local State")),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = state["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any]
        else { return [:] }
        return cache.compactMapValues { ($0 as? [String: Any])?["name"] as? String }
    }

    public func read() throws -> BrowsingData {
        BrowsingData(visits: try visits(), bookmarks: bookmarks())
    }

    private func visits() throws -> [BrowsingData.Visit] {
        let copy = FileManager.default.temporaryDirectory.appending(path: "Kaizu-import-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: copy) }
        for name in ["History", "History-journal", "History-wal"] {
            try? FileManager.default.copyItem(at: directory.appending(path: name), to: copy.appending(path: name))
        }

        var handle: OpaquePointer?
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_open(copy.appending(path: "History").path, &handle) == SQLITE_OK,
              sqlite3_prepare_v2(handle, """
                SELECT url, title, visit_count, last_visit_time FROM urls
                WHERE hidden = 0 AND last_visit_time > 0
                ORDER BY last_visit_time DESC
                LIMIT ?1
                """, -1, &statement, nil) == SQLITE_OK
        else { throw BrowsingData.Failure.unreadable }
        sqlite3_bind_int64(statement, 1, Int64(BrowsingData.visitLimit))

        var visits: [BrowsingData.Visit] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let address = sqlite3_column_text(statement, 0),
                  let url = BrowsingData.webURL(String(cString: address))
            else { continue }
            visits.append(BrowsingData.Visit(
                url: url,
                title: sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "",
                count: max(Int(sqlite3_column_int64(statement, 2)), 1),
                lastVisit: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3) / 1_000_000 - Self.epochOffset)
            ))
        }
        return visits
    }

    private struct BookmarksFile: Decodable {
        struct Node: Decodable {
            var type: String?
            var name: String?
            var url: String?
            var children: [Node]?
        }

        struct Roots: Decodable {
            var bar: Node?
            var other: Node?
            var synced: Node?

            enum CodingKeys: String, CodingKey {
                case bar = "bookmark_bar", other, synced
            }
        }

        var roots: Roots
    }

    /// The bookmarks bar comes first and unnested; a browser without any
    /// (Arc keeps nothing here) has no file.
    private func bookmarks() -> [BrowsingData.Bookmark] {
        guard let data = try? Data(contentsOf: directory.appending(path: "Bookmarks")),
              let roots = try? JSONDecoder().decode(BookmarksFile.self, from: data).roots
        else { return [] }
        func items(_ nodes: [BookmarksFile.Node]) -> [BrowsingData.Bookmark] {
            nodes.compactMap { node in
                if node.type == "url" {
                    return node.url.flatMap(BrowsingData.webURL).map { .page(title: node.name ?? "", url: $0) }
                }
                let children = items(node.children ?? [])
                return children.isEmpty ? nil : .folder(name: node.name ?? "Bookmarks", children: children)
            }
        }
        return items(roots.bar?.children ?? []) + items([roots.other, roots.synced].compactMap(\.self))
    }
}
