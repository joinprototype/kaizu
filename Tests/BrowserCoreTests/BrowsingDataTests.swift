import Foundation
import SQLite3
import Testing
@testable import BrowserCore

@Suite struct BrowsingDataTests {
    private static let example = URL(string: "https://example.com/")!
    private static let docs = URL(string: "https://docs.example.com/guide")!

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "browsing-data-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A `History` database with Chromium's table, as (url, title, visits, seconds since 1970, hidden).
    private func makeHistory(at file: URL, _ rows: [(String, String?, Int, Double, Int)]) {
        var db: OpaquePointer?
        sqlite3_open(file.path, &db)
        defer { sqlite3_close(db) }
        sqlite3_exec(db, """
            CREATE TABLE urls (id INTEGER PRIMARY KEY, url LONGVARCHAR, title LONGVARCHAR,
                visit_count INTEGER DEFAULT 0, typed_count INTEGER DEFAULT 0,
                last_visit_time INTEGER DEFAULT 0, hidden INTEGER DEFAULT 0)
            """, nil, nil, nil)
        for (url, title, visits, seconds, hidden) in rows {
            let time = Int64((seconds + 11_644_473_600) * 1_000_000)
            let name = title.map { "'\($0)'" } ?? "NULL"
            sqlite3_exec(db, "INSERT INTO urls (url, title, visit_count, last_visit_time, hidden) VALUES ('\(url)', \(name), \(visits), \(time), \(hidden))", nil, nil, nil)
        }
    }

    // MARK: - Chromium

    @Test func readsChromiumHistoryNewestFirst() throws {
        let profile = try folder()
        makeHistory(at: profile.appending(path: "History"), [
            ("https://example.com/", "Example", 3, 1_700_000_000, 0),
            ("https://docs.example.com/guide", nil, 0, 1_750_000_000, 0),
            ("https://example.com/hidden", "Hidden", 1, 1_750_000_001, 1),
            ("file:///Users/someone/page.html", "Local", 9, 1_750_000_002, 0),
            ("chrome://settings", "Settings", 9, 1_750_000_003, 0),
        ])
        let data = try ChromiumProfile(browser: "Chrome", title: "Chrome", directory: profile).read()
        #expect(data.visits.map(\.url) == [Self.docs, Self.example])
        #expect(data.visits[0].title == "")
        #expect(data.visits[0].count == 1)
        #expect(data.visits[1].count == 3)
        #expect(abs(data.visits[1].lastVisit.timeIntervalSince1970 - 1_700_000_000) < 0.001)
        #expect(data.bookmarks.isEmpty)
    }

    @Test func leavesTheBrowsersFilesAlone() throws {
        let profile = try folder()
        let history = profile.appending(path: "History")
        makeHistory(at: history, [("https://example.com/", "Example", 1, 1_700_000_000, 0)])
        let before = try Data(contentsOf: history)
        _ = try ChromiumProfile(browser: "Chrome", title: "Chrome", directory: profile).read()
        #expect(try Data(contentsOf: history) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: profile.path) == ["History"])
    }

    @Test func aDamagedHistoryIsAnError() throws {
        let profile = try folder()
        try Data("not a database".utf8).write(to: profile.appending(path: "History"))
        #expect(throws: BrowsingData.Failure.unreadable) {
            try ChromiumProfile(browser: "Chrome", title: "Chrome", directory: profile).read()
        }
    }

    @Test func readsChromiumBookmarks() throws {
        let profile = try folder()
        makeHistory(at: profile.appending(path: "History"), [])
        try Data("""
            {"roots": {
              "bookmark_bar": {"type": "folder", "name": "Bookmarks bar", "children": [
                {"type": "url", "name": "Example", "url": "https://example.com/"},
                {"type": "url", "name": "Tool", "url": "javascript:alert(1)"},
                {"type": "folder", "name": "Work", "children": [
                  {"type": "url", "name": "Guide", "url": "https://docs.example.com/guide"}
                ]},
                {"type": "folder", "name": "Empty", "children": []}
              ]},
              "other": {"type": "folder", "name": "Other bookmarks", "children": [
                {"type": "url", "name": "Again", "url": "https://example.com/"}
              ]},
              "synced": {"type": "folder", "name": "Mobile bookmarks", "children": []}
            }}
            """.utf8).write(to: profile.appending(path: "Bookmarks"))
        let data = try ChromiumProfile(browser: "Chrome", title: "Chrome", directory: profile).read()
        #expect(data.bookmarks == [
            .page(title: "Example", url: Self.example),
            .folder(name: "Work", children: [.page(title: "Guide", url: Self.docs)]),
            .folder(name: "Other bookmarks", children: [.page(title: "Again", url: Self.example)]),
        ])
    }

    @Test func findsProfilesByTheirNames() throws {
        let support = try folder()
        let chrome = support.appending(path: "Google/Chrome", directoryHint: .isDirectory)
        for name in ["Profile 2", "Default", "Guest Profile", "Profile 3"] {
            let directory = chrome.appending(path: name, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if name != "Profile 3" {
                try Data().write(to: directory.appending(path: "History"))
            }
        }
        try Data(#"{"profile": {"info_cache": {"Default": {"name": "Personal"}, "Profile 2": {"name": "Work"}}}}"#.utf8)
            .write(to: chrome.appending(path: "Local State"))
        let arc = support.appending(path: "Arc/User Data/Default", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: arc, withIntermediateDirectories: true)
        try Data().write(to: arc.appending(path: "History"))

        #expect(ChromiumProfile.installed(in: support).map(\.title) == ["Arc", "Chrome: Personal", "Chrome: Work"])
        #expect(try ChromiumProfile.installed(in: folder()).isEmpty)
    }

    // MARK: - Safari

    private static let historyJSON = #"""
        {
          "metadata": {"browser_name": "Safari", "browser_version": "26.0", "data_type": "history",
                       "export_time_usec": 1790000000000000, "schema_version": 1},
          "history": [
            {"url": "https://example.com/", "time_usec": 1700000000000000, "visits_count": 4, "title": "Example"},
            {"url": "https://docs.example.com/guide", "time_usec": 1750000000000000, "visits_count": 1},
            {"url": "https://example.com/hop", "time_usec": 1750000000000001, "visits_count": 1,
             "destination_url": "https://example.com/", "destination_time_usec": 1700000000000000},
            {"url": "https://example.com/gone", "time_usec": 1750000000000002, "visits_count": 1,
             "latest_visit_was_load_failure": true},
            {"url": "file:///etc/hosts", "time_usec": 1750000000000003, "visits_count": 1}
          ]
        }
        """#

    @Test func readsSafariHistory() throws {
        let visits = try #require(SafariExport.history(fromJSON: Data(Self.historyJSON.utf8)))
        #expect(visits.map(\.url) == [Self.docs, Self.example])
        #expect(visits[1].count == 4)
        #expect(visits[1].title == "Example")
        #expect(visits[1].lastVisit == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func otherSafariFilesArentHistory() {
        let cards = #"{"metadata": {"data_type": "payment_cards"}, "payment_cards": [{"card_number": "4111"}]}"#
        #expect(SafariExport.history(fromJSON: Data(cards.utf8)) == nil)
        #expect(SafariExport.history(fromJSON: Data("nonsense".utf8)) == nil)
    }

    @Test func readsNetscapeBookmarks() {
        let html = """
            <!DOCTYPE NETSCAPE-Bookmark-file-1>
            <TITLE>Bookmarks</TITLE><H1>Bookmarks</H1>
            <DL><p>
              <DT><A HREF="https://example.com/" ADD_DATE="1">Tom &amp; Jerry</A>
              <DT><H3 FOLDED>Work</H3>
              <DL><p>
                <DT><A href="https://docs.example.com/guide">Guide &lt;new&gt;</A>
                <DT><H3>Nested</H3>
                <DL><p>
                  <DT><A HREF="https://example.com/a?x=1&amp;y=2">A</A>
                </DL><p>
                <DT><H3>Empty</H3>
                <DL><p></DL><p>
              </DL><p>
              <DT><A HREF="javascript:alert(1)">Tool</A>
              <DT><H3 id="com.apple.ReadingList">Reading List</H3>
              <DL><p>
                <DT><A HREF="https://example.com/later">Later</A>
            """
        #expect(SafariExport.bookmarks(fromHTML: html) == [
            .page(title: "Tom & Jerry", url: Self.example),
            .folder(name: "Work", children: [
                .page(title: "Guide <new>", url: Self.docs),
                .folder(name: "Nested", children: [.page(title: "A", url: URL(string: "https://example.com/a?x=1&y=2")!)]),
            ]),
            .folder(name: "Reading List", children: [.page(title: "Later", url: URL(string: "https://example.com/later")!)]),
        ])
    }

    /// Passwords and cards stay in the archive: nothing is unpacked beside it.
    @Test func readsOnlyHistoryAndBookmarksFromAnArchive() throws {
        let files = try folder()
        try Data(Self.historyJSON.utf8).write(to: files.appending(path: "History.json"))
        try Data(Self.historyJSON.utf8).write(to: files.appending(path: "History [Work].json"))
        try Data(#"<DL><DT><A HREF="https://example.com/">Example</A></DL>"#.utf8).write(to: files.appending(path: "Bookmarks.html"))
        try Data("Title,URL,Username,Password\nExample,https://example.com/,me,secret".utf8).write(to: files.appending(path: "Passwords.csv"))
        try Data(#"{"metadata": {"data_type": "payment_cards"}}"#.utf8).write(to: files.appending(path: "PaymentCards.json"))
        let output = try folder()
        let archive = output.appending(path: "Export.zip")
        let zip = try Process.run(URL(fileURLWithPath: "/usr/bin/zip"), arguments: ["-j", "-q", archive.path] + FileManager.default.contentsOfDirectory(atPath: files.path).map { files.appending(path: $0).path })
        zip.waitUntilExit()

        let data = try SafariExport.read(archive)
        #expect(data.visits.map(\.url) == [Self.docs, Self.docs, Self.example, Self.example])
        #expect(data.bookmarks == [.page(title: "Example", url: Self.example)])
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path) == ["Export.zip"])
    }

    @Test func aFileThatIsntAnExportIsAnError() throws {
        let file = try folder().appending(path: "Export.zip")
        try Data("not a zip".utf8).write(to: file)
        #expect(throws: BrowsingData.Failure.unreadable) { try SafariExport.read(file) }
    }

    // MARK: - Into pinned tabs

    @Test func bookmarksBecomeAClosedFolderOfNewPages() throws {
        let data = BrowsingData(bookmarks: [
            .page(title: "Example", url: Self.example),
            .page(title: "Example again", url: Self.example),
            .folder(name: "Work", children: [.page(title: "Guide", url: Self.docs)]),
            .folder(name: "Pinned already", children: [.page(title: "Pinned", url: URL(string: "https://pinned.example.com/")!)]),
        ])
        let (folder, count) = try #require(data.bookmarkFolder(named: "Chrome Bookmarks", skipping: [URL(string: "https://pinned.example.com/")!]))
        #expect(count == 2)
        #expect(folder.name == "Chrome Bookmarks")
        #expect(!folder.isExpanded)
        #expect(folder.children.count == 2)
        guard case .tab(let tab) = folder.children[0], case .folder(let work) = folder.children[1] else {
            Issue.record("wrong shape")
            return
        }
        #expect(tab.pinnedURL == Self.example)
        #expect(work.name == "Work")
        #expect(!work.isExpanded)
    }

    @Test func nothingNewMakesNoFolder() {
        let data = BrowsingData(bookmarks: [.page(title: "Example", url: Self.example)])
        #expect(data.bookmarkFolder(named: "Bookmarks", skipping: [Self.example]) == nil)
        #expect(BrowsingData().bookmarkFolder(named: "Bookmarks", skipping: []) == nil)
    }

    @Test func bookmarksStopAtTheLimit() throws {
        let pages = (0..<(BrowsingData.bookmarkLimit + 10)).map { BrowsingData.Bookmark.page(title: "", url: URL(string: "https://example.com/\($0)")!) }
        let result = try #require(BrowsingData(bookmarks: pages).bookmarkFolder(named: "Bookmarks", skipping: []))
        #expect(result.count == BrowsingData.bookmarkLimit)
        #expect(result.folder.children.count == BrowsingData.bookmarkLimit)
    }

    // MARK: - Into history

    @Test func addingHistoryMergesAndCanBeTakenBack() async throws {
        let store = try HistoryStore(fileURL: folder().appending(path: "history.sqlite"))
        let profile = UUID()
        let then = Date(timeIntervalSince1970: 1_700_000_000)
        let later = Date(timeIntervalSince1970: 1_750_000_000)
        await store.recordVisit(profile: profile, url: Self.example, title: "Mine", at: later)

        let visits = [
            BrowsingData.Visit(url: Self.example, title: "Theirs", count: 5, lastVisit: then),
            BrowsingData.Visit(url: Self.docs, title: "Guide", count: 2, lastVisit: then),
        ]
        #expect(await store.add(visits, profile: profile) == [Self.docs])
        #expect(await store.add(visits, profile: profile) == [])

        let entries = await store.recent(profile: profile)
        #expect(entries.count == 2)
        let mine = try #require(entries.first { $0.url == Self.example })
        #expect(mine.title == "Mine")
        #expect(mine.visitCount == 5)
        #expect(mine.lastVisit == later)
        #expect(entries.first { $0.url == Self.docs }?.visitCount == 2)

        await store.remove([Self.docs], profile: profile)
        #expect(await store.recent(profile: profile).map(\.url) == [Self.example])
    }
}
