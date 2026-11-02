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
    /// `notifyingTabs` are spared, and rebuilt if they'd otherwise be paused,
    /// except on a memory warning (no `interval`).
    func hibernateIdleTabs(olderThan interval: TimeInterval = hibernateAfter) async {
        let now = Date()
        let cutoff = now.addingTimeInterval(-interval)
        let spared = interval > 0 ? notifyingTabs : []
        for tab in Set(spaces.flatMap(\.allTabs)) where tab.isLoaded && !isOnScreen(tab) {
            // Re-checked after the await: the user may have switched to it meanwhile.
            guard (tab.lastActiveAt ?? now) <= cutoff, await !tab.isBusy, !isOnScreen(tab) else { continue }
            if !spared.contains(tab) {
                tab.hibernate()
            } else if tab.needsRebuildToNotify {
                tab.rebuildToNotify()
            }
        }
    }

    /// Sites you let notify you have no push service behind them, so one tab
    /// of each has to be running: the one best placed to, which hibernation
    /// and archiving leave alone.
    var notifyingTabs: Set<BrowserTab> {
        func standing(_ tab: BrowserTab) -> Int {
            if isOnScreen(tab) { return 4 }
            guard tab.isLoaded else { return tab.pinnedURL == nil ? 0 : 1 }
            return tab.needsRebuildToNotify ? 2 : 3
        }
        var chosen: [String: BrowserTab] = [:]
        for tab in spaces.flatMap(\.allTabs) {
            guard let host = tab.notifyingHost else { continue }
            if chosen[host].map({ standing($0) < standing(tab) }) ?? true {
                chosen[host] = tab
            }
        }
        return Set(chosen.values)
    }

    /// One of them would otherwise wait to be clicked after a relaunch or a
    /// memory warning, or if its page process died.
    func wakeTabsThatNotify() {
        for tab in notifyingTabs where !tab.isLoaded {
            tab.activate()
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
