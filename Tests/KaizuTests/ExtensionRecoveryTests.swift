import AppKit
import Testing
import WebKit
@testable import Kaizu

@MainActor
struct ExtensionRecoveryTests {
    @Test func unavailableRegistrationsSurviveOtherInstallsAndRecoverWithTheirSiteGrants() async throws {
        _ = NSApplication.shared
        let suite = "dev.kaizu.tests.extensions." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let folderID = UUID(), safariID = UUID()
        let vendor = directory.appending(path: "Vendor.app")
        let site = "https://fixture.example/*"
        // Older versions saved these records without display names.
        let seed: [[String: Any]] = [
            ["id": folderID.uuidString, "kind": "folder", "path": "/old/support/" + folderID.uuidString,
             "additionalSites": [site]],
            ["id": safariID.uuidString, "kind": "safariApp", "path": vendor.path],
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: seed), forKey: "installedExtensions")

        func host() -> ExtensionHost {
            ExtensionHost(defaults: defaults, directory: directory, configuration: .nonPersistent())
        }
        let first = host()
        let control = directory.appending(path: "Control")
        try createExtension(at: control, name: "Control")
        await first.install(from: control, askFirst: false)
        let controlID = try #require(first.installed.first?.id)

        let restored = host()
        await restored.loadInstalled()
        #expect(Set(restored.unavailable.map(\.id)) == [folderID, safariID])
        #expect(restored.unavailable.first { $0.id == safariID }?.name == "Vendor")
        #expect(restored.installed.map(\.id) == [controlID])
        try createExtension(at: directory.appending(path: folderID.uuidString), name: "Recovered")
        async let retry: Void = restored.load(folderID)
        await restored.load(folderID)
        await retry
        let recovered = try #require(restored.installed.first { $0.id == folderID })
        #expect(restored.installed.count == 2)
        #expect(restored.unavailable.map(\.id) == [safariID])
        #expect(restored.additionalSites(for: recovered) == [site])
        #expect(recovered.context.hasAccess(to: try #require(URL(string: "https://fixture.example/page"))))
        #expect(recovered.context.baseURL.host == folderID.uuidString.lowercased())

        try FileManager.default.createDirectory(at: vendor, withIntermediateDirectories: true)
        restored.uninstall(safariID)
        #expect(FileManager.default.fileExists(atPath: vendor.path))
        let final = host()
        await final.loadInstalled()
        #expect(final.unavailable.isEmpty)
        #expect(Set(final.installed.map(\.id)) == [folderID, controlID])
    }

    private func createExtension(at url: URL, name: String) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let manifest: [String: Any] = ["name": name, "manifest_version": 3, "version": "1.0"]
        try JSONSerialization.data(withJSONObject: manifest).write(to: url.appending(path: "manifest.json"))
    }
}
