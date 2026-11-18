import CryptoKit
import Foundation

/// Check the signing key or a staged package with the release browser’s verification key.
@main
struct CheckReleasePackage {
    static func main() {
        do {
            try check(CommandLine.arguments)
        } catch {
            fail("Release verification failed: \(error)")
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }

    private static func check(_ arguments: [String]) throws {
        if arguments.count == 3, arguments[1] == "--check-key" {
            let encoded = try String(contentsOfFile: arguments[2], encoding: .utf8)
            guard let raw = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw),
                  key.publicKey.rawRepresentation.base64EncodedString() == ReleaseUpdateKey.base64 else {
                fail("The signing key does not match Kaizu’s release update key.")
            }
            return
        }
        guard arguments.count == 3 else { fail("Expected a feed and update archive.") }
        let feed = try JSONDecoder().decode(UpdateRelease.self, from: Data(contentsOf: URL(filePath: arguments[1])))
        guard let archive = feed.archive, let signature = feed.signature else { fail("Incomplete release feed") }
        let zip = URL(filePath: arguments[2])
        guard zip.lastPathComponent == archive.lastPathComponent else { fail("Feed points to a different archive") }
        let folder = FileManager.default.temporaryDirectory.appending(path: "kaizu-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let stage = UpdateStage(folder: folder, bundleID: "com.joinprototype.kaizu", publicKey: ReleaseUpdateKey.base64)
        let app = try stage.stage(archive: zip, build: feed.build, signature: signature)
        guard app.version == feed.version else { fail("The feed and app versions differ") }
        print("Verified update signature, bundle identity, code signature and build \(app.build)")
    }
}
