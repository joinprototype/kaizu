import AppKit
@testable import Kaizu
import Testing
@testable import WebEngine
import WebKit

@MainActor
struct ImportedRuleListTests {
    @Test func importRestoreDisableAndRemove() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("imported")
        let picked = root.appendingPathComponent("Example.json")
        let json = #"[{"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".example"}}]"#
        try json.write(to: picked, atomically: true, encoding: .utf8)
        let initial = ImportedRuleLists(directory: folder)
        await initial.restore()
        try await initial.add(picked)
        let entry = try #require(initial.entries.first)
        #expect(entry.name == "Example.json")
        #expect(await rejects { try await initial.add(picked) })
        try "broken".write(to: picked, atomically: true, encoding: .utf8)
        #expect(await rejects { try await initial.add(picked) })
        #expect(initial.entries.count == 1)
        try FileManager.default.removeItem(at: picked)
        let cache = try #require(WKContentRuleListStore(url: folder.appendingPathComponent("Compiled")))
        try await cache.removeContentRuleList(forIdentifier: entry.id)

        let restored = ImportedRuleLists(directory: folder)
        await restored.restore()
        #expect(restored.problems.isEmpty)
        try await checkPage(restored, hidden: true)
        try await restored.setEnabled(false, id: entry.id)
        let disabled = ImportedRuleLists(directory: folder)
        await disabled.restore()
        #expect(disabled.entries.first?.enabled == false)
        try await checkPage(disabled, hidden: false)
        try await disabled.setEnabled(true, id: entry.id)
        try await checkPage(disabled, hidden: true)
        try await disabled.remove(entry.id)
        try await checkPage(disabled, hidden: false)
        let removed = ImportedRuleLists(directory: folder)
        await removed.restore()
        #expect(removed.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(entry.id + ".json").path))
    }

    @Test func preservesUnreadableCatalog() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let index = root.appendingPathComponent("lists.json")
        let original = Data("[unfinished".utf8)
        try original.write(to: index)
        let lists = ImportedRuleLists(directory: root)
        await lists.restore()
        #expect(lists.indexError != nil)
        #expect(await rejects { try await lists.add(index) })
        #expect(try Data(contentsOf: index) == original)
    }

    private func rejects(_ action: () async throws -> Void) async -> Bool {
        do { try await action(); return false } catch { return true }
    }

    private func checkPage(_ lists: ImportedRuleLists, hidden: Bool) async throws {
        _ = NSApplication.shared
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        lists.install(on: config.userContentController)
        let frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        let view = WKWebView(frame: frame, configuration: config)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        view.loadHTMLString("<!doctype html><p class='example'>banner</p><p id='control'>ordinary</p>",
                            baseURL: URL(string: "https://example.test/"))
        let query = """
            document.readyState === "complete" && document.querySelector("#control") &&
            [getComputedStyle(document.querySelector(".example")).display, getComputedStyle(document.querySelector("#control")).display]
            """
        let expected = [hidden ? "none" : "block", "block"]
        for _ in 0..<100 {
            if let displays = try? await view.evaluateJavaScript(query) as? [String], displays == expected { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Rendered fixture did not reach expected styles: \(expected)")
    }
}
