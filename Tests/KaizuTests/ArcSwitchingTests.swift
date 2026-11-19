// Only debug builds route AppModel writes to the disposable KAIZU_SUPPORT directory.
#if DEBUG
import AppKit
import BrowserCore
import Testing
import WebKit
@testable import Kaizu

/// scripts/test-arc-switching.sh runs the import and restart in separate processes.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["KAIZU_SWITCH_PHASE"] != nil))
struct ArcSwitchingTests {
    @Test func workspace() async throws {
        _ = NSApplication.shared
        let env = ProcessInfo.processInfo.environment
        let support = try #require(env["KAIZU_SUPPORT"])
        let directory = URL(fileURLWithPath: support, isDirectory: true).standardizedFileURL
        let root = directory.deletingLastPathComponent()
        try #require(directory.lastPathComponent == "support" && root.lastPathComponent.hasPrefix("kaizu-switching."))
        try #require(FileManager.default.fileExists(atPath: root.appending(path: ".switching-trial").path))
        let files = SessionFiles(directory: directory)
        let session = try files.open()
        if env["KAIZU_SWITCH_PHASE"] == "cleanup" {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            let view = WKWebView(frame: .zero, configuration: config)
            for profile in try #require(session?.record.profiles) {
                try await WKWebsiteDataStore.remove(forIdentifier: profile.id)
            }
            withExtendedLifetime(view) {}
            return
        }
        let app = AppModel(session: session)
        let store = app.regularFront
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "BrowserCoreTests/Fixtures/StorableSidebar.json")
        var sidebar = try ArcSidebar.load(from: source)
        sidebar.spaces[0].today[0].url = first
        let privateProfile = Profile(name: "Private", isPrivate: true)
        let privateSpace = Space(profile: privateProfile, name: "Private", symbol: "lock", hue: 0.5)
        let hidden = BrowserStore(app: app, record: WindowRecord(), privateSpace: privateSpace)
        let secret = hidden.openTab(URL(string: "about:blank#secret"), select: false)
        if env["KAIZU_SWITCH_PHASE"] == "seed" {
            try #require(session == nil)
            try await importAndArchive(sidebar, store: store, hidden: hidden, secret: secret)
        } else {
            try #require(env["KAIZU_SWITCH_PHASE"] == "restart")
            try await checkRestoredWorkspace(sidebar, store: store, hidden: hidden, secret: secret)
        }
    }

    private let first = URL(string: "data:text/html,first")!
    private let last = URL(string: "data:text/html,later")!

    private func importAndArchive(_ sidebar: ArcSidebar, store: BrowserStore, hidden: BrowserStore, secret: BrowserTab) async throws {
        let app = store.app
        let preview = store.arcImport(of: sidebar, includesToday: true)
        store.importFromArc(preview)
        app.save()
        #expect(store.spaces.map(\.name) == preview.summary.map(\.name))
        #expect(store.spaces.map(\.profile.name) == preview.summary.compactMap(\.profileName))
        #expect(preview.summary.map(\.sidebarPosition) == [1, 2])
        #expect(store.spaces.map { $0.today.count } == preview.summary.map(\.today))
        #expect(store.spaces.map { $0.pinned.tabs.count } == preview.summary.map(\.pinned))
        try #require(store.arcImport(of: sidebar, includesToday: true).tabCount == 0)
        let work = store.activeSpace
        let tab = try #require(work.today.first { $0.url == first })
        tab.activate()
        try await wait(first, tab)
        tab.webView.load(URLRequest(url: last))
        try await wait(last, tab)
        tab.customTitle = "Quarterly notes"
        let live = store.arcImport(of: sidebar, includesToday: true)
        #expect(live.tabCount == 0)
        tab.lastActiveAt = .distantPast
        app.archiveStaleTabs()
        try #require(store.archive.first?.tab.customTitle == "Quarterly notes")
        #expect(hidden.archive.isEmpty && hidden.activeSpace.today == [secret])
        let afterArchive = store.arcImport(of: sidebar, includesToday: true)
        #expect(afterArchive.tabCount == 0)
        var extended = sidebar
        var addition = sidebar.spaces[0].pinned.tabs[0]
        addition.url = URL(string: "https://additional.example.test/")!
        extended.spaces[0].pinned.append(.tab(addition))
        let extra = store.arcImport(of: extended, includesToday: false)
        try #require(extra.tabCount == 1)
        let pins = work.pinned.map(\.record)
        store.importFromArc(extra)
        store.undoToast()
        #expect(work.pinned.map(\.record) == pins)
        // Keep imported pages the later repeat-import check expects to find.
        for tab in work.today { store.move(tab, to: .pinned(folder: nil, before: nil)) }
        try clearTodayInSplit(store)
        app.saveTabStates()
        app.save()
    }

    private func clearTodayInSplit(_ store: BrowserStore) throws {
        let work = store.activeSpace
        let left = store.openTab(URL(string: "about:blank#left"))
        let right = store.openTab(URL(string: "about:blank#right"), select: false)
        store.addToSplit(right)
        store.move(left, to: .pinned(folder: nil, before: nil))
        store.move(right, to: .pinned(folder: nil, before: nil))
        let temporary = store.openTab(URL(string: "about:blank#temporary"), select: false)
        store.addToSplit(temporary)
        let originalLayout = work.splitLayout
        try #require(store.selectedTab === temporary)
        store.clearToday(in: work)
        #expect(work.split == [left.id, right.id])
        #expect(store.shownTabs == [left, right])
        store.undoToast()
        #expect(work.splitLayout == originalLayout && work.today.contains(temporary))
        store.select(temporary)
        store.clearToday(in: work)
        store.closeSplit()
        store.undoToast()
        #expect(work.split.isEmpty && work.today.contains(temporary))
        store.select(left)
        store.addToSplit(right)
        store.addToSplit(temporary)
        store.clearToday(in: work)
        #expect(work.record.split == [left.id, right.id])
    }

    private func checkRestoredWorkspace(_ sidebar: ArcSidebar, store: BrowserStore, hidden: BrowserStore, secret: BrowserTab) async throws {
        let app = store.app
        let work = store.activeSpace
        try #require(work.name == "Work" && store.spaces.count == 2)
        #expect(store.shownTabs.compactMap { $0.url?.fragment } == ["left", "right"])
        let entry = try #require(store.matchingArchivedTabs("quarterly").first)
        hidden.reopen(entry)
        let other = app.addWindow(WindowRecord(activeSpaceID: store.spaces[1].id))
        other.reopen(entry)
        try #require(store.archive.contains(entry) && hidden.activeSpace.today == [secret])
        store.perform(.archived(entry), mode: .newTab)
        let restored = try #require(store.selectedTab)
        try await wait(last, restored)
        #expect(restored.webView.backForwardList.backItem?.url == first)
        #expect(restored.profile === work.profile && work.today.contains(restored))
        #expect(restored.customTitle == "Quarterly notes" && store.archive.isEmpty)
        #expect(store.arcImport(of: sidebar, includesToday: true).tabCount == 0)
    }

    private func wait(_ page: URL, _ tab: BrowserTab) async throws {
        let deadline = ContinuousClock.now + .seconds(8)
        while (tab.webView.url != page || tab.webView.isLoading) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(tab.webView.url == page && !tab.webView.isLoading)
    }
}
#endif
