import Foundation

enum BundledResource {
    /// Looks in the app bundle, falling back to the repo's Resources folder
    /// when the bare executable runs from `swift run` or Xcode.
    static func url(named name: String, extension ext: String, in subdirectory: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return url
        }
        #if DEBUG
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Support
            .deletingLastPathComponent()  // Kaizu
            .deletingLastPathComponent()  // Sources
            .deletingLastPathComponent()
        let url = repository.appending(path: "Resources/\(subdirectory)/\(name).\(ext)")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
        #else
        return nil
        #endif
    }
}
