#if DEBUG
import AppKit
import BrowserCore

extension DebugHooks {
    static func qaBrowsingData(_ store: BrowserStore) {
        func log(_ text: String) {
            DebugHooks.log("QA browsing data: \(text)")
        }
        UtilityWindows.showBrowsingDataImport(app: store.app)
        log("browsers \(ChromiumProfile.installed().map(\.title))")
        guard let path = ProcessInfo.processInfo.environment["KAIZU_IMPORT"] else {
            Task {
                try? await Task.sleep(for: .seconds(3))
                saveShot(ofWindow: "Import Browsing Data")
            }
            return
        }
        let source: BrowsingDataImportView.Source
        if path == "arc", let arc = ChromiumProfile.installed().first(where: { $0.browser == "Arc" }) {
            source = .browser(arc)
        } else if path.hasSuffix(".zip") || path.hasSuffix(".html") || path.hasSuffix(".json") {
            source = .file(URL(fileURLWithPath: path))
        } else {
            source = .browser(ChromiumProfile(browser: "QA", title: "QA", directory: URL(fileURLWithPath: path)))
        }
        Task {
            do {
                let data = try await source.read().data(history: .all, bookmarks: .all)
                let space = store.activeSpace
                let profile = space.profile.id
                let pinnedBefore = space.pinned.count
                let bookmarks = data.bookmarkFolder(named: source.folderName, skipping: space.pinnedAddresses)
                log("read \(data.visits.count) pages, \(bookmarks?.count ?? 0) new bookmarks")
                await store.app.importBrowsingData(data.visits, bookmarks: bookmarks, into: space)
                let stored = await store.history?.recent(profile: profile, limit: 100_000).count ?? 0
                log("toast \(store.toast?.message ?? "none")")
                log("stored \(stored) pages, pinned \(pinnedBefore) -> \(space.pinned.count), folder open \(space.pinned.folders.last?.isExpanded ?? false)")
                log("second time \(data.bookmarkFolder(named: source.folderName, skipping: space.pinnedAddresses)?.count ?? 0) new bookmarks")
                let moved = store.openTab(URL(string: "https://example.com/moved-in"))
                if let folder = space.pinned.folders.last {
                    store.move(moved, to: .pinned(folder: folder, before: nil))
                }
                store.undoToast()
                try? await Task.sleep(for: .seconds(1))
                log("a tab moved into the folder survives undo: \(space.today.contains(moved) && !moved.isDiscarded && moved.pinnedURL == nil)")
                let left = await store.history?.recent(profile: profile, limit: 100_000).count ?? 0
                log("after undo \(left) pages, pinned \(space.pinned.count)")
            } catch {
                log("failed \(error)")
            }
        }
    }
}
#endif
