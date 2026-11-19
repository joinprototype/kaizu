#if DEBUG
import AppKit
import BrowserCore

extension DebugHooks {
    static func checkBookmarkImportUndo(in store: BrowserStore) async {
        precondition(ProcessInfo.processInfo.environment["KAIZU_SUPPORT"] != nil)
        let space = store.activeSpace
        precondition(space.allTabs.isEmpty)
        let data = BrowsingData(bookmarks: [
            .page(title: "First", url: URL(string: "about:blank#first")!),
            .page(title: "Second", url: URL(string: "about:blank#second")!)
        ])
        let bookmarks = data.bookmarkFolder(named: "Imported", skipping: [])!
        let original = store.openTab(URL(string: "about:blank#original")!)
        await store.app.importBrowsingData([], bookmarks: bookmarks, into: space)
        let folder = space.pinned.folders.first!
        let imported = folder.children.tabs
        store.move(original, to: .pinned(folder: folder, before: nil))
        let secondWindow = store.app.openWindow(on: space)
        secondWindow.move(imported[0], to: .favorites(before: nil))
        secondWindow.delete(folder)
        secondWindow.select(imported[1])
        store.undoToast()
        let singleOriginal = space.today.map(\.id) == [original.id] && !original.isDiscarded
        let importsGone = space.pinned.isEmpty && space.profile.favorites.isEmpty && imported.allSatisfy(\.isDiscarded)
        let selectionRepaired = secondWindow.selectedTabIDs[space.id] != imported[1].id
        print("Bookmark Undo after folder deletion: one original tab \(singleOriginal), imported tabs removed \(importsGone), second window repaired \(selectionRepaired)")
        guard singleOriginal && importsGone && selectionRepaired else { exit(1) }

        let repeatImport = data.bookmarkFolder(named: "Imported again", skipping: space.pinnedAddresses)!
        await store.app.importBrowsingData([], bookmarks: repeatImport, into: space)
        secondWindow.move(original, to: .pinned(folder: space.pinned.folders.first!, before: nil))
        store.app.regularFront.undoToast()
        precondition(space.pinned.isEmpty && space.today.map(\.id) == [original.id])
        precondition(original.pinnedURL == nil && !original.isDiscarded)
        store.app.save()
    }
}
#endif
