import Foundation

/// Keeps memory in check and tabs where you left them: background tabs idle
/// for half an hour hibernate (their web view is freed), everything
/// hibernates on a system memory warning, and each tab's back/forward state
/// is saved so it survives hibernation and relaunches.
extension AppModel {
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
                self.wakeTabsThatNotify()
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
    /// One tab of each site allowed to notify is spared, and rebuilt if it
    /// would otherwise be paused, except on a memory warning (no `interval`).
    func hibernateIdleTabs(olderThan interval: TimeInterval = hibernateAfter) async {
        let now = Date()
        let cutoff = now.addingTimeInterval(-interval)
        let tabs = Set(spaces.flatMap(\.allTabs))
        var listening = Set(tabs.filter { $0.canKeepRunning && isOnScreen($0) }.compactMap { $0.url?.host() })
        // Ones already running first, so none is rebuilt for nothing.
        for tab in tabs.sorted(by: { !$0.needsRebuildToNotify && $1.needsRebuildToNotify })
        where tab.isLoaded && !isOnScreen(tab) {
            let listens = interval > 0 && tab.canKeepRunning && tab.url?.host().map { listening.insert($0).inserted } == true
            // Re-checked after the await: the user may have switched to it meanwhile.
            guard (tab.lastActiveAt ?? now) <= cutoff, await !tab.isBusy, !isOnScreen(tab) else { continue }
            if !listens {
                tab.hibernate()
            } else if tab.needsRebuildToNotify {
                tab.rebuildToNotify()
            }
        }
    }

    /// Sites you let notify you have no push service behind them: one tab of
    /// each has to be running. Otherwise it would wait to be clicked after a
    /// relaunch or a memory warning, or if its page process died.
    func wakeTabsThatNotify() {
        let tabs = spaces.flatMap(\.allTabs).filter(\.canKeepRunning)
        var awake = Set(tabs.filter(\.isLoaded).compactMap { $0.url?.host() })
        for tab in tabs {
            if let host = tab.url?.host(), awake.insert(host).inserted {
                tab.activate()
            }
        }
    }

    private func isOnScreen(_ tab: BrowserTab) -> Bool {
        stores.contains { $0.selectedTab === tab || $0.peek === tab || $0.activeSpace.splitTabs.contains(tab) }
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
