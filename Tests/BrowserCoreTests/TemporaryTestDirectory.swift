import Foundation

/// Each test owns its fixture files, including SQLite journals and unpacked updates.
final class TemporaryTestDirectory: Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "kaizu-test-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
