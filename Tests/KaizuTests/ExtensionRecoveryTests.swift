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

    @Test func addingTheSameSafariAppKeepsOneRegistrationAcrossRestarts() async throws {
        let suite = "dev.kaizu.tests.safari." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vendor = directory.appending(path: "Vendor.app", directoryHint: .isDirectory)
        let alias = directory.appending(path: "Alias.app", directoryHint: .isDirectory)
        let plugin = vendor.appending(path: "Contents/PlugIns/Fixture.appex", directoryHint: .isDirectory)
        try createExtension(at: plugin.appending(path: "Contents/Resources"), name: "Safari Fixture")
        let executable = plugin.appending(path: "Contents/MacOS/Fixture")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: executable)
        let info: [String: Any] = [
            "CFBundleIdentifier": suite, "CFBundleName": "Fixture", "CFBundleExecutable": "Fixture",
            "CFBundlePackageType": "XPC!", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
            "NSExtension": ["NSExtensionPointIdentifier": "com.apple.Safari.web-extension"],
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: plugin.appending(path: "Contents/Info.plist"))
        let signer = try Process.run(URL(fileURLWithPath: "/usr/bin/codesign"), arguments: ["--force", "--sign", "-", plugin.path])
        signer.waitUntilExit()
        try #require(signer.terminationStatus == 0)
        let bundle = try #require(Bundle(url: plugin))
        _ = try await WKWebExtension(appExtensionBundle: bundle)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: vendor)

        func host() -> ExtensionHost {
            ExtensionHost(defaults: defaults, directory: directory, configuration: .nonPersistent())
        }
        let original = host()
        async let first: Void = original.install(from: vendor, askFirst: false)
        async let second: Void = original.install(from: alias, askFirst: false)
        _ = await (first, second)
        let installed = try #require(original.installed.first)
        #expect(original.installed.count == 1)
        await original.install(from: vendor, askFirst: false)
        #expect(original.installed.map(\.id) == [installed.id])

        let reopened = host()
        #expect(reopened.hasSafariApp(alias))
        await reopened.install(from: alias, askFirst: false)
        await reopened.loadInstalled()
        #expect(reopened.installed.map(\.id) == [installed.id])
        reopened.uninstall(installed.id)
        #expect(!reopened.hasSafariApp(vendor))
        await reopened.install(from: vendor, askFirst: false)
        #expect(reopened.installed.count == 1)
        #expect(reopened.installed.first?.id != installed.id)
    }

    private func createExtension(at url: URL, name: String) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let manifest: [String: Any] = ["name": name, "manifest_version": 3, "version": "1.0"]
        try JSONSerialization.data(withJSONObject: manifest).write(to: url.appending(path: "manifest.json"))
    }
}
