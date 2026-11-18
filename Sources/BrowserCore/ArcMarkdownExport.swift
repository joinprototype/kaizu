import Foundation

extension ArcSidebar {
    /// Arc's Export Data command writes spaces and folders as headings and tabs as URL bullets.
    /// The file doesn't identify profiles or distinguish Today tabs from pinned links.
    static func parseMarkdownExport(_ data: Data) throws -> ArcSidebar {
        guard let text = String(data: data, encoding: .utf8) else { throw ArcSidebarError.unreadable }
        var spaces: [Space] = []
        var folders: [(depth: Int, name: String, items: [Item])] = []
        var skipped = 0
        var hasLinks = false

        func append(_ item: Item) {
            if folders.isEmpty { spaces[spaces.count - 1].pinned.append(item) }
            else { folders[folders.count - 1].items.append(item) }
        }

        func closeFolders(atOrBelow depth: Int) {
            while let last = folders.last, last.depth >= depth {
                let folder = folders.removeLast()
                if !folder.items.isEmpty { append(.folder(name: folder.name, children: folder.items)) }
            }
        }

        for raw in text.drop(while: { $0 == "\u{feff}" }).split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let depth = line.prefix(while: { $0 == "#" }).count
            if depth > 0 {
                let rest = line.dropFirst(depth)
                guard rest.isEmpty || rest.first?.isWhitespace == true else { continue }
                let name = rest.trimmingCharacters(in: .whitespaces)
                closeFolders(atOrBelow: depth)
                if depth == 1 {
                    // Give each space a distinct profile key. An export gives us no evidence that two share logins.
                    spaces.append(Space(name: name.isEmpty ? "Untitled Space" : name, profile: "export-\(spaces.count)",
                                        hue: nil, pinned: [], today: []))
                } else if !spaces.isEmpty, folders.count < 32 {
                    folders.append((depth, name.isEmpty ? "Folder" : name, []))
                }
                continue
            }
            guard !spaces.isEmpty, line.hasPrefix("- ") else { continue }
            let address = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            guard let url = URL(string: address, encodingInvalidCharacters: false), url.isWebPage,
                  let host = url.host(), !host.isEmpty else { skipped += 1; continue }
            append(.tab(Tab(title: host + (url.path == "/" ? "" : url.path), url: url)))
            hasLinks = true
        }
        closeFolders(atOrBelow: 1)
        guard hasLinks else { throw ArcSidebarError.unreadable }
        return ArcSidebar(spaces: spaces, favorites: [:], skipped: skipped)
    }
}
