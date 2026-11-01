import Foundation

/// Safari's File → Export Browsing Data to File…, which is how its data
/// leaves it: Safari's own files need Full Disk Access. The .zip also holds
/// passwords and payment cards, so this streams single entries into memory,
/// never unpacks it, and never opens anything but JSON and HTML. File names
/// are localized and profiles get their own, so history is recognized by what
/// the file says it is.
public enum SafariExport {
    /// A .zip from Safari, or a lone history .json or bookmarks .html (any
    /// browser's bookmarks export is this format).
    public static func read(_ file: URL) throws -> BrowsingData {
        var data: BrowsingData
        switch file.pathExtension.lowercased() {
        case "zip":
            data = try readArchive(file)
        case "json":
            guard let visits = history(fromJSON: try Data(contentsOf: file)) else { throw BrowsingData.Failure.unreadable }
            data = BrowsingData(visits: visits)
        default:
            data = BrowsingData(bookmarks: bookmarks(fromHTML: try String(contentsOf: file, encoding: .utf8)))
        }
        data.visits = Array(data.visits.sorted { $0.lastVisit > $1.lastVisit }.prefix(BrowsingData.visitLimit))
        return data
    }

    private static func readArchive(_ file: URL) throws -> BrowsingData {
        guard let listing = unzip(["-Z1", file.path]) else { throw BrowsingData.Failure.unreadable }
        var data = BrowsingData()
        for name in String(decoding: listing, as: UTF8.self).split(separator: "\n").map(String.init) {
            let kind = (name as NSString).pathExtension.lowercased()
            guard kind == "json" || kind == "html" else { continue }
            // unzip reads names as patterns.
            let pattern = name.replacingOccurrences(of: #"([\\*?\[\]])"#, with: #"\\$1"#, options: .regularExpression)
            guard let entry = unzip(["-p", file.path, pattern]) else { continue }
            if kind == "html" {
                data.bookmarks += bookmarks(fromHTML: String(decoding: entry, as: UTF8.self))
            } else if let visits = history(fromJSON: entry) {
                data.visits += visits
            }
        }
        return data
    }

    private static func unzip(_ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    private struct HistoryFile: Decodable {
        struct Metadata: Decodable {
            var dataType: String?

            enum CodingKeys: String, CodingKey {
                case dataType = "data_type"
            }
        }

        struct Item: Decodable {
            var url: String
            var title: String?
            var time: Double
            var count: Int?
            var redirectsTo: String?
            var failed: Bool?

            enum CodingKeys: String, CodingKey {
                case url, title
                case time = "time_usec"
                case count = "visits_count"
                case redirectsTo = "destination_url"
                case failed = "latest_visit_was_load_failure"
            }
        }

        var metadata: Metadata?
        var history: [Item]?
    }

    /// Nil for any other kind of file. Pages that only redirected on, or
    /// failed to load, aren't places you've been.
    static func history(fromJSON data: Data) -> [BrowsingData.Visit]? {
        guard let file = try? JSONDecoder().decode(HistoryFile.self, from: data),
              file.metadata?.dataType == "history", let items = file.history
        else { return nil }
        return items.compactMap { item in
            guard item.redirectsTo == nil, item.failed != true, let url = BrowsingData.webURL(item.url) else { return nil }
            return BrowsingData.Visit(
                url: url, title: item.title ?? "", count: max(item.count ?? 1, 1),
                lastVisit: Date(timeIntervalSince1970: item.time / 1_000_000)
            )
        }
    }

    /// The Netscape bookmarks format: `<DL>` lists of `<A HREF>` pages, each
    /// list named by the `<H3>` before it. Old and loosely closed, so only
    /// those tags count, and a list left open ends with the file.
    static func bookmarks(fromHTML html: String) -> [BrowsingData.Bookmark] {
        let tags = #/<dl\b[^>]*>|<\/dl\s*>|<h3\b[^>]*>(.*?)<\/h3\s*>|<a\b[^>]*?href="([^"]*)"[^>]*>(.*?)<\/a\s*>/#
            .ignoresCase().dotMatchesNewlines()
        var lists: [(name: String?, items: [BrowsingData.Bookmark])] = [(nil, [])]
        var nextListName: String?

        func closeList() {
            guard lists.count > 1 else { return }
            let list = lists.removeLast()
            if let name = list.name {
                if !list.items.isEmpty {
                    lists[lists.count - 1].items.append(.folder(name: name, children: list.items))
                }
            } else {
                lists[lists.count - 1].items += list.items
            }
        }

        for match in html.matches(of: tags) {
            if let name = match.output.1 {
                nextListName = decoded(name)
            } else if let address = match.output.2 {
                if let url = BrowsingData.webURL(decoded(address)) {
                    lists[lists.count - 1].items.append(.page(title: decoded(match.output.3 ?? ""), url: url))
                }
            } else if match.output.0.hasPrefix("</") {
                closeList()
            } else {
                lists.append((nextListName, []))
                nextListName = nil
            }
        }
        while lists.count > 1 {
            closeList()
        }
        return lists[0].items
    }

    private static func decoded(_ text: Substring) -> String {
        // &amp; last, so "&amp;lt;" stays the text "&lt;".
        [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")]
            .reduce(text.trimmingCharacters(in: .whitespacesAndNewlines)) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}
