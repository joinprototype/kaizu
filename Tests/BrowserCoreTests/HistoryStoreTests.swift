import Foundation
import Testing
@testable import BrowserCore

@Suite struct HistoryStoreTests {
    let personal = UUID()
    let work = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeStore() throws -> HistoryStore {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID()).sqlite")
        return try HistoryStore(fileURL: file)
    }

    @Test func ranksFrequentRecentVisitsFirst() async throws {
        let store = try makeStore()
        let docs = URL(string: "https://docs.swift.org/")!
        let blog = URL(string: "https://swift.org/blog/")!
        await store.recordVisit(profile: personal, url: blog, title: "Swift Blog", at: now)
        for _ in 0..<3 {
            await store.recordVisit(profile: personal, url: docs, title: "Swift Docs", at: now)
        }
        let results = await store.search("swift", profile: personal, now: now)
        #expect(results.map(\.url) == [docs, blog])
        #expect(results.first?.visitCount == 3)
    }

    @Test func keepsProfilesSeparate() async throws {
        let store = try makeStore()
        await store.recordVisit(profile: work, url: URL(string: "https://jira.example.com/")!, title: "Jira", at: now)
        #expect(await store.search("jira", profile: personal, now: now).isEmpty)
        #expect(await store.search("jira", profile: work, now: now).count == 1)
    }

    @Test func revisitKeepsTitleWhenNewOneIsEmpty() async throws {
        let store = try makeStore()
        let url = URL(string: "https://example.com/")!
        await store.recordVisit(profile: personal, url: url, title: "Example", at: now)
        await store.recordVisit(profile: personal, url: url, title: "", at: now)
        #expect(await store.recent(profile: personal).first?.title == "Example")
    }

    @Test func treatsWildcardsInQueriesLiterally() async throws {
        let store = try makeStore()
        await store.recordVisit(profile: personal, url: URL(string: "https://example.com/a")!, title: "100% juice", at: now)
        await store.recordVisit(profile: personal, url: URL(string: "https://example.com/b")!, title: "plain", at: now)
        #expect(await store.search("100%", profile: personal, now: now).map(\.title) == ["100% juice"])
    }

    @Test func removesSingleEntry() async throws {
        let store = try makeStore()
        let keep = URL(string: "https://keep.example.com/")!
        let drop = URL(string: "https://drop.example.com/")!
        await store.recordVisit(profile: personal, url: keep, title: "Keep", at: now)
        await store.recordVisit(profile: personal, url: drop, title: "Drop", at: now)
        await store.remove(drop, profile: personal)
        #expect(await store.recent(profile: personal).map(\.url) == [keep])
    }

    @Test func ignoresNonWebURLsAndClears() async throws {
        let store = try makeStore()
        await store.recordVisit(profile: personal, url: URL(string: "about:blank")!, title: "", at: now)
        await store.recordVisit(profile: personal, url: URL(string: "https://example.com/")!, title: "Example", at: now)
        #expect(await store.recent(profile: personal).count == 1)
        await store.removeAll(profile: personal)
        #expect(await store.recent(profile: personal).isEmpty)
    }
}
