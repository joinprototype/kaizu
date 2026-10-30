import BrowserCore
import Foundation

/// A folder in a space's pinned section (Arc's tab groups). Folders nest.
@MainActor @Observable
final class Folder: Identifiable {
    let id: UUID
    var name: String
    var isExpanded: Bool
    var children: [SidebarItem]

    init(id: UUID = UUID(), name: String, isExpanded: Bool = true, children: [SidebarItem] = []) {
        self.id = id
        self.name = name
        self.isExpanded = isExpanded
        self.children = children
    }
}

/// An entry in the pinned section: a tab or a folder.
enum SidebarItem: Identifiable {
    case tab(BrowserTab)
    case folder(Folder)

    var id: UUID {
        switch self {
        case .tab(let tab): tab.id
        case .folder(let folder): folder.id
        }
    }

    @MainActor
    var record: SidebarItemRecord {
        switch self {
        case .tab(let tab):
            .tab(tab.record)
        case .folder(let folder):
            .folder(FolderRecord(id: folder.id, name: folder.name, isExpanded: folder.isExpanded, children: folder.children.map(\.record)))
        }
    }
}

// MARK: - Tree operations

@MainActor
extension [SidebarItem] {
    /// All tabs, depth-first in sidebar order.
    var tabs: [BrowserTab] {
        flatMap { item -> [BrowserTab] in
            switch item {
            case .tab(let tab): [tab]
            case .folder(let folder): folder.children.tabs
            }
        }
    }

    /// Tabs not hidden inside collapsed folders.
    var visibleTabs: [BrowserTab] {
        flatMap { item -> [BrowserTab] in
            switch item {
            case .tab(let tab): [tab]
            case .folder(let folder): folder.isExpanded ? folder.children.visibleTabs : []
            }
        }
    }

    /// All folders, depth-first.
    var folders: [Folder] {
        flatMap { item -> [Folder] in
            guard case .folder(let folder) = item else { return [] }
            return [folder] + folder.children.folders
        }
    }

    /// Removes the entry with `id` wherever it sits in the tree.
    @discardableResult
    mutating func remove(id: UUID) -> SidebarItem? {
        if let index = firstIndex(where: { $0.id == id }) {
            return remove(at: index)
        }
        for folder in folders {
            if let index = folder.children.firstIndex(where: { $0.id == id }) {
                return folder.children.remove(at: index)
            }
        }
        return nil
    }

    /// The folder directly containing `id`, or nil at top level / not found.
    func parent(of id: UUID) -> Folder? {
        folders.first { folder in folder.children.contains { $0.id == id } }
    }
}

extension Array where Element: Identifiable {
    /// Inserts before the element with `id`, or appends when `id` is nil or absent.
    mutating func insert(_ element: Element, before id: Element.ID?) {
        let index = id.flatMap { id in firstIndex { $0.id == id } } ?? endIndex
        insert(element, at: index)
    }
}
