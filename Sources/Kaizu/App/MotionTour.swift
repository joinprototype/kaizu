#if DEBUG
import AppKit
import BrowserCore
import QuartzCore

/// KAIZU_DEBUG=tour: runs the main interactions one after another while
/// a display link times every frame, then logs dropped frames for each
/// (a frame counts as dropped when it took more than 1.5 refresh
/// intervals). Needs the window on an awake screen; use a separate copy
/// (KAIZU_SUPPORT and its own bundle id), since it opens tabs and spaces.
@MainActor
final class MotionTour: NSObject {
    private let store: BrowserStore
    private var link: CADisplayLink?
    private var frames: [CFTimeInterval] = []
    private var interval: CFTimeInterval = 1.0 / 60

    init(store: BrowserStore) {
        self.store = store
    }

    func run() async {
        try? await Task.sleep(for: .seconds(2))
        guard let view = store.window?.contentView else { return log("no window") }
        let link = view.displayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        defer { link.invalidate() }

        let first = store.openTab(URL(string: "https://example.com/"))
        let second = store.openTab(URL(string: "https://example.org/"))
        if store.spaces.count < 2 {
            store.commit(SpaceDraft(name: "Tour", hue: 0.6, symbol: "star", profile: .existing(store.activeSpace.profile.id)))
        }
        store.switchTo(store.spaces[0])
        store.select(second)
        try? await Task.sleep(for: .seconds(3))

        await measure("command bar open") { store.showCommandBar(.newTab) }
        await measure("command bar close") { store.dismissCommandBar() }
        await measure("sidebar hide") { store.toggleSidebar() }
        await measure("sidebar show") { store.toggleSidebar() }
        await measure("space switch") { store.switchTo(store.spaces[1]) }
        await measure("space switch back") { store.switchTo(store.spaces[0]) }
        await measure("space swipe") { await self.swipe() }
        await measure("swipe back") { store.switchTo(store.spaces[0]) }
        await measure("tab switch") { store.select(first) }
        await measure("split open") { store.addToSplit(second) }
        await measure("split close") { store.closeSplit() }
        await measure("peek open") { store.peek(URL(string: "https://example.net/")!, from: first) }
        await measure("peek close") { store.closePeek() }
        await measure("new tab") { store.openTab(URL(string: "https://example.com/tour")) }
        await measure("close tab") { store.closeSelectedTab() }
        await measure("zoom toast") { store.selectedTab?.zoom(by: 0.1) }
        await measure("zoom toast again") { store.selectedTab?.zoom(by: -0.1) }
        log("done (refresh \(Int((1 / interval).rounded())) Hz)")
    }

    /// Runs `action`, then records the frames of the next 0.8 s.
    private func measure(_ label: String, _ action: () async -> Void) async {
        frames = []
        let start = CACurrentMediaTime()
        await action()
        try? await Task.sleep(for: .milliseconds(800))
        guard frames.count > 1 else { return log("\(label): no frames drawn (is the screen awake and unlocked?)") }
        let durations = zip(frames.dropFirst(), frames).map { (at: $1 - start, length: $0 - $1) }
        let dropped = durations.filter { $0.length > interval * 1.5 }
        let worst = durations.map(\.length).max() ?? 0
        // When each slow frame started, after the action: early ones are the
        // first layout of new views, later ones are the animation itself.
        let when = dropped.map { "\(Int(($0.at * 1000).rounded()))" }.joined(separator: ",")
        log("\(label): \(durations.count) frames, \(dropped.count) dropped\(when.isEmpty ? "" : " at \(when) ms"), worst \(Int((worst * 1000).rounded())) ms")
        try? await Task.sleep(for: .milliseconds(400))
    }

    /// A two-finger swipe to the next space, as the trackpad monitor sees it.
    private func swipe() async {
        let start = ProcessInfo.processInfo.systemUptime
        store.spaceSwipeTravel = 0
        store.spaceSwipeSamples = []
        var travel: CGFloat = 0
        for step in 1...14 {
            travel = CGFloat(step) * 14
            store.trackSpaceSwipe(to: travel, at: start + Double(step) / 60)
            try? await Task.sleep(for: .milliseconds(16))
        }
        store.spaceSwipeTravel = nil
        store.finishSpaceSwipe(travel: travel, at: start + 14.0 / 60, switches: true)
    }

    @objc private func frame(_ link: CADisplayLink) {
        frames.append(link.timestamp)
        let nominal = link.targetTimestamp - link.timestamp
        if nominal > 0 { interval = nominal }
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("QA tour \(message)\n".utf8))
    }
}
#endif
