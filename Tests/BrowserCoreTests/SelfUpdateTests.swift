import BrowserCore
import CryptoKit
import Foundation
import Testing

/// Real archives, real codesign, real helper script: only the key is made up.
struct SelfUpdateTests {
    private let key = Curve25519.Signing.PrivateKey()
    private let bundleID = "com.example.kaizu"
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "kaizu-update-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private var publicKey: String { key.publicKey.rawRepresentation.base64EncodedString() }

    private func stage(_ name: String = "stage") -> UpdateStage {
        UpdateStage(folder: root.appending(path: name, directoryHint: .isDirectory), bundleID: bundleID, publicKey: publicKey)
    }

    private func shell(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
    }

    /// A tiny signed app, as a zip like the one scripts/release.sh makes.
    private func archive(bundleID id: String? = nil, build: Int = 2, unsigned: Bool = false, named: String = "Kaizu.app") throws -> URL {
        let place = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let app = place.appending(path: named, directoryHint: .isDirectory)
        let macOS = app.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: macOS.appending(path: "Kaizu"))
        let info: [String: Any] = [
            "CFBundleIdentifier": id ?? bundleID, "CFBundleVersion": String(build),
            "CFBundleShortVersionString": "0.1.1", "CFBundleExecutable": "Kaizu", "CFBundlePackageType": "APPL",
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: app.appending(path: "Contents/Info.plist"))
        if !unsigned { try shell("/usr/bin/codesign", ["--force", "--sign", "-", app.path]) }
        let zip = place.appending(path: "update.zip")
        try shell("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path])
        return zip
    }

    private func signature(_ zip: URL, build: Int = 2) throws -> String {
        try key.signature(for: UpdateSignature.message(archive: zip, build: build)).base64EncodedString()
    }

    private func staged(_ zip: URL, build: Int = 2, signature: String) throws -> StagedUpdate {
        try stage().stage(archive: zip, build: build, signature: signature)
    }

    private func rejected(_ expected: UpdateFailure, _ body: () throws -> StagedUpdate) throws {
        let folder = stage().folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(throws: expected) { _ = try body() }
        #expect(!FileManager.default.fileExists(atPath: folder.path), "a failure leaves nothing staged")
    }

    @Test func goodUpdateStages() throws {
        let zip = try archive()
        let update = try staged(zip, signature: signature(zip))
        #expect(update.build == 2)
        #expect(update.version == "0.1.1")
        #expect(update.app.lastPathComponent == "Kaizu.app")
        #expect(FileManager.default.fileExists(atPath: update.app.path))
    }

    @Test func oneFlippedByteIsRejected() throws {
        let zip = try archive()
        let good = try signature(zip)
        var bytes = try Data(contentsOf: zip)
        bytes[bytes.count / 2] ^= 0x01
        try bytes.write(to: zip)
        try rejected(.badSignature) { try staged(zip, signature: good) }
    }

    @Test func aSignatureForAnotherBuildIsRejected() throws {
        // The same archive, offered as a newer build than it was signed for.
        let zip = try archive(build: 3)
        let forBuildTwo = try signature(zip, build: 2)
        try rejected(.badSignature) { try staged(zip, build: 3, signature: forBuildTwo) }
    }

    @Test func aSignatureFromAnotherKeyIsRejected() throws {
        let zip = try archive()
        let other = Curve25519.Signing.PrivateKey()
        let forged = try other.signature(for: UpdateSignature.message(archive: zip, build: 2)).base64EncodedString()
        try rejected(.badSignature) { try staged(zip, signature: forged) }
    }

    @Test func nonsenseSignaturesAreRejected() throws {
        let zip = try archive()
        try rejected(.badSignature) { try staged(zip, signature: "not base64!") }
        try rejected(.badSignature) { try staged(zip, signature: "") }
    }

    @Test func anotherAppIsRejected() throws {
        let zip = try archive(bundleID: "com.example.other")
        try rejected(.wrongApp) { try staged(zip, signature: signature(zip)) }
    }

    @Test func anAppOfAnotherBuildIsRejected() throws {
        let zip = try archive(build: 2)
        try rejected(.wrongBuild) { try staged(zip, build: 3, signature: signature(zip, build: 3)) }
    }

    @Test func anUnsignedAppIsRejected() throws {
        let zip = try archive(unsigned: true)
        try rejected(.badCodeSignature) { try staged(zip, signature: signature(zip)) }
    }

    @Test func somethingThatIsNotAnAppIsRejected() throws {
        let zip = try archive(named: "Kaizu.txt")
        try rejected(.wrongArchive) { try staged(zip, signature: signature(zip)) }
    }

    @Test func aFeedWithoutAnArchiveStillDecodes() throws {
        let json = #"{"version":"0.1.1","build":2,"url":"https://example.com/download"}"#
        let release = try JSONDecoder().decode(UpdateRelease.self, from: Data(json.utf8))
        #expect(release.archive == nil)
        #expect(release.signature == nil)
    }

    @Test func onlyAWritableLocalAppCanReplaceItself() throws {
        let folder = root.appending(path: "Applications", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let app = folder.appending(path: "Kaizu.app", directoryHint: .isDirectory)
        #expect(UpdatePlace.canReplace(app: app))
        #expect(!UpdatePlace.canReplace(app: URL(fileURLWithPath: "/Volumes/Kaizu/Kaizu.app")))
        #expect(!UpdatePlace.canReplace(app: URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/y/d/Kaizu.app")))
        #expect(!UpdatePlace.canReplace(app: folder.appending(path: "Kaizu")), "a bare binary from swift run")
        #expect(!UpdatePlace.canReplace(app: URL(fileURLWithPath: "/System/Applications/Kaizu.app")))
    }

    // MARK: - The swap

    private func app(_ text: String, at folder: URL) throws -> URL {
        let app = folder.appending(path: "Kaizu.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: app.appending(path: "marker"))
        return app
    }

    private func marker(_ app: URL) -> String? {
        (try? Data(contentsOf: app.appending(path: "marker"))).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// A process that exits shortly, standing in for Kaizu, and the swap behind it.
    private func swap(app: URL, staged: URL) async throws {
        let quitting = Process()
        quitting.executableURL = URL(fileURLWithPath: "/bin/sleep")
        quitting.arguments = ["0.3"]
        try quitting.run()
        try UpdateSwap.launch(pid: quitting.processIdentifier, app: app, staged: staged, relaunch: false)
        #expect(marker(app) == "old", "nothing moves while the app still runs")
        quitting.waitUntilExit()
        try await Task.sleep(for: .seconds(1))
    }

    private func neighbours(of app: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: app.deletingLastPathComponent().path).sorted()
    }

    @Test func swapReplacesTheAppOnceItHasQuit() async throws {
        let live = root.appending(path: "live", directoryHint: .isDirectory)
        let cache = root.appending(path: "cache", directoryHint: .isDirectory)
        let current = try app("old", at: live)
        let staged = try app("new", at: cache)
        try await swap(app: current, staged: staged)
        #expect(marker(current) == "new")
        #expect(try neighbours(of: current) == ["Kaizu.app"], "no backup left behind")
        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }

    @Test func swapLeavesTheAppAloneWhenTheUpdateIsGone() async throws {
        let live = root.appending(path: "live", directoryHint: .isDirectory)
        let current = try app("old", at: live)
        try await swap(app: current, staged: root.appending(path: "missing.app"))
        #expect(marker(current) == "old")
        #expect(try neighbours(of: current) == ["Kaizu.app"])
    }

    @Test func swapRestoresTheOldAppIfTheNewOneCannotGoIn() async throws {
        // A path with a trailing folder that can't be renamed over: the final
        // move fails after the old app is aside, and the old one must come back.
        let live = root.appending(path: "live", directoryHint: .isDirectory)
        let current = try app("old", at: live)
        let staged = try app("new", at: root.appending(path: "cache", directoryHint: .isDirectory))
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        let failing = "mv() { if [ \"$2\" = \"$app\" ] && [ \"$1\" = \"$incoming\" ]; then return 1; fi; command mv \"$@\"; }\n" + UpdateSwap.script
        helper.arguments = ["-c", failing, "test", "999999", current.path, staged.path, "0"]
        try helper.run()
        helper.waitUntilExit()
        #expect(marker(current) == "old")
        #expect(try neighbours(of: current) == ["Kaizu.app"])
    }
}
