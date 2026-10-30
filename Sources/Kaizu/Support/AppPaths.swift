import Foundation

enum AppPaths {
    /// `~/Library/Application Support/Kaizu/`, created on first use.
    static let support: URL = {
        #if DEBUG
        // QA launches can keep to a scratch folder, away from the real session.
        if let path = ProcessInfo.processInfo.environment["KAIZU_SUPPORT"] {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        #endif
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appending(path: "Kaizu", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
}
