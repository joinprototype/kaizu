import Foundation

/// Each file contains WebKit's back/forward state for one regular tab.
/// The quit snapshot waits for earlier sweeps, including their cleanup of closed tabs.
public final class TabStateFiles: Sendable {
    private let directory: URL
    private let queue = DispatchQueue(label: "com.joinprototype.kaizu.tab-states", qos: .utility)

    public init(directory: URL) {
        self.directory = directory
    }

    public func read(_ id: UUID) -> Data? {
        queue.sync {
            try? Data(contentsOf: directory.appending(path: "\(id).state"))
        }
    }

    public func save(_ states: [UUID: Data], inBackground: Bool = false) {
        let write: @Sendable () -> Void = { [directory] in
            let files = FileManager.default
            try? files.createDirectory(at: directory, withIntermediateDirectories: true)
            for (id, data) in states {
                try? data.write(to: directory.appending(path: "\(id).state"), options: .atomic)
            }
            let existing = (try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in existing where file.pathExtension == "state" {
                if let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent), states[id] == nil {
                    try? files.removeItem(at: file)
                }
            }
        }
        if inBackground {
            queue.async(execute: write)
        } else {
            queue.sync(execute: write)
        }
    }
}
