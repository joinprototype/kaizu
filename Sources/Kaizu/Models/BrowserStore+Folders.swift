import SwiftUI

extension BrowserStore {
    /// Creates a folder at the top of the pinned section, optionally holding `tab`.
    func newFolder(with tab: BrowserTab? = nil) {
        guard !isPrivate else { return }
        let folder = Folder(name: "New Folder")
        withAnimation(Motion.snap) {
            activeSpace.pinned.insert(.folder(folder), at: 0)
        }
        if let tab {
            move(tab, to: .pinned(folder: folder, before: nil))
        }
        renamingFolderID = folder.id
        scheduleSave()
    }

    /// An empty name goes back to the page's title.
    func rename(_ tab: BrowserTab, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        tab.customTitle = name.isEmpty ? nil : name
        renamingTabID = nil
        scheduleSave()
    }

    func rename(_ folder: Folder, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            folder.name = name
        }
        renamingFolderID = nil
        scheduleSave()
    }

    func toggle(_ folder: Folder) {
        withAnimation(Motion.snap) {
            folder.isExpanded.toggle()
        }
        scheduleSave()
    }

    /// Removes the folder; nothing is lost, its tabs move to the top of Today.
    func delete(_ folder: Folder) {
        let space = activeSpace
        let tabs = folder.children.tabs
        withAnimation(Motion.snap) {
            space.pinned.remove(id: folder.id)
            for tab in tabs.reversed() {
                tab.pinnedURL = nil
                space.today.insert(tab, at: 0)
            }
        }
        scheduleSave()
    }
}
