import Foundation

/// Keeps memory in check and tabs where you left them: background tabs idle
/// for half an hour hibernate (their web view is freed), everything
/// hibernates on a system memory warning, and each tab's back/forward state
/// is saved so it survives hibernation and relaunches.
extension BrowserStore {
    static let hibernateAfter: TimeInterval = 30 * 60
    private static let hibernationSweep: Duration = .seconds(5 * 60)

    private static var tabStatesDirectory: URL {
        AppPaths.support.appending(path: "TabStates", directoryHint: .isDirectory)
    }

    func startHibernating() {
        Task { [weak self] in
            while let self {
                try? await Task.sleep(for: Self.hibernationSweep)
                await self.hibernateIdleTabs()
                self.saveTabStates(inBackground: true)
            }
        }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in await self?.hibernateIdleTabs(olderThan: 0) }
        }
        source.resume()
        memoryPressureSource = source
    }

    /// Hibernates loaded tabs that aren't on screen, haven't been used for
    /// `interval`, and aren't playing media or using the camera/microphone.
    func hibernateIdleTabs(olderThan interval: TimeInterval = hibernateAfter, now: Date = Date()) async {
        let cutoff = now.addingTimeInterval(-interval)
        for tab in Set(spaces.flatMap(\.allTabs)) where tab.isLoaded && !isOnScreen(tab) {
            // Re-checked after the await: the user may have switched to it meanwhile.
            guard (tab.lastActiveAt ?? now) <= cutoff, await !tab.isBusy, !isOnScreen(tab) else { continue }
            tab.hibernate()
        }
    }

    private func isOnScreen(_ tab: BrowserTab) -> Bool {
        tab === selectedTab || tab === peek || activeSpace.splitTabs.contains(tab)
    }

    // MARK: - Saved tab state

    /// Writes every tab's back/forward state and forgets closed tabs'. The
    /// periodic sweep writes off the main thread; quitting writes in place.
    func saveTabStates(inBackground: Bool = false) {
        let states = Set(spaces.flatMap(\.allTabs)).reduce(into: [String: Data]()) { states, tab in
            states["\(tab.id).state"] = tab.currentState
        }
        let directory = Self.tabStatesDirectory
        let write: @Sendable () -> Void = {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, state) in states {
                try? state.write(to: directory.appending(path: name), options: .atomic)
            }
            // Forget closed and archived tabs.
            let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            for file in files where states[file] == nil {
                try? FileManager.default.removeItem(at: directory.appending(path: file))
            }
        }
        if inBackground {
            Task.detached(priority: .utility, operation: write)
        } else {
            write()
        }
    }

    func savedTabState(for id: UUID) -> Data? {
        try? Data(contentsOf: Self.tabStatesDirectory.appending(path: "\(id).state"))
    }
}
