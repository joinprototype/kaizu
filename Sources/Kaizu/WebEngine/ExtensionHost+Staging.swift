import Foundation

extension ExtensionHost {
    /// Off the main thread: a big extension takes a moment to unpack.
    @concurrent
    nonisolated static func stage(_ url: URL, in directory: URL, at destination: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if url.pathExtension == "zip" {
            try unzip(url, to: destination)
        } else {
            try FileManager.default.copyItem(at: url, to: destination)
        }
    }

    nonisolated private static func unzip(_ archive: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
        // Zips often wrap everything in one folder; use it if the manifest is inside.
        let contents = (try? FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)) ?? []
        if !FileManager.default.fileExists(atPath: destination.appending(path: "manifest.json").path),
           contents.count == 1, let inner = contents.first,
           FileManager.default.fileExists(atPath: inner.appending(path: "manifest.json").path) {
            let staging = destination.deletingLastPathComponent().appending(path: UUID().uuidString)
            try FileManager.default.moveItem(at: inner, to: staging)
            try FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: staging, to: destination)
        }
    }
}
