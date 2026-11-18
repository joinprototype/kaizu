import Foundation

/// Run with the browser's own SelfUpdate.swift against a freshly packaged feed.
@main
struct CheckReleasePackage {
    static func main() throws {
        let arguments = CommandLine.arguments
        let feed = try JSONDecoder().decode(UpdateRelease.self, from: Data(contentsOf: URL(filePath: arguments[1])))
        guard let archive = feed.archive, let signature = feed.signature else { fatalError("Incomplete release feed") }
        let zip = URL(filePath: arguments[1]).deletingLastPathComponent().appending(path: "updates/" + archive.lastPathComponent)
        let stage = UpdateStage(folder: URL(filePath: arguments[3]), bundleID: "com.joinprototype.kaizu", publicKey: arguments[2])
        let app = try stage.stage(archive: zip, build: feed.build, signature: signature)
        guard app.version == feed.version else { fatalError("The feed and app versions differ") }
        print("Verified update signature, bundle identity, code signature and build \(app.build)")
    }
}
