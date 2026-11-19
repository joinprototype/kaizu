import BrowserCore
import Foundation

/// Manual and automatic checks share the download for each build.
final class UpdatePreparation {
    private(set) var staged: StagedUpdate?
    private var pending: [Int: Task<StagedUpdate, Error>] = [:]

    private let root: URL

    init(root: URL) {
        self.root = root
    }

    func folder(for build: Int) -> URL {
        root.appending(path: String(build), directoryHint: .isDirectory)
    }

    func prepare(build: Int, download: @escaping @MainActor () async throws -> StagedUpdate) -> Task<StagedUpdate, Error> {
        if let staged, staged.build >= build { return Task { staged } }
        if let task = pending[build] { return task }

        let task = Task {
            defer { pending[build] = nil }
            let ready: StagedUpdate
            do {
                ready = try await download()
            } catch {
                if let staged, staged.build >= build { return staged }
                throw error
            }
            guard let previous = staged else {
                staged = ready
                return ready
            }
            guard previous.build != ready.build else { return previous }
            let obsolete: URL
            if previous.build > ready.build {
                obsolete = folder(for: ready.build)
            } else {
                staged = ready
                obsolete = folder(for: previous.build)
            }
            // Only retire verified builds. Other folders may still be downloading.
            await Self.remove(obsolete)
            // Another check may have finished during cleanup.
            return staged ?? ready
        }
        pending[build] = task
        return task
    }

    @concurrent
    private nonisolated static func remove(_ folder: URL) async {
        try? FileManager.default.removeItem(at: folder)
    }
}
