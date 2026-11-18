import BrowserCore

/// Manual and automatic checks share the download for each build.
@MainActor
final class UpdatePreparation {
    private(set) var staged: StagedUpdate?
    private var pending: [Int: Task<StagedUpdate, Error>] = [:]

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
            if let staged, staged.build >= build { return staged }
            staged = ready
            return ready
        }
        pending[build] = task
        return task
    }
}
