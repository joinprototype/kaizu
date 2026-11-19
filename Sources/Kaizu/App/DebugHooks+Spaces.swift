#if DEBUG
import AppKit
import BrowserCore

extension DebugHooks {
    /// `appearance`: a light space and an automatic one; logs the window's look in each.
    static func qaAppearance(_ store: BrowserStore) {
        store.activeSpace.appearance = .light
        store.updateWindowAppearance()
        let first = store.activeSpace
        store.commit(SpaceDraft(name: "QA", hue: 0.6, symbol: "star", profile: .existing(first.profile.id)))
        let auto = store.window?.effectiveAppearance.name.rawValue ?? "?"
        store.switchTo(first)
        let light = store.window?.effectiveAppearance.name.rawValue ?? "?"
        log("QA appearance: light space \(light), auto space \(auto)")
    }

    /// `swipe`: swipes like the trackpad monitor would: a slow drag past
    /// halfway (switches), a short flick (switches), a short slow drag
    /// (springs back). Needs two spaces; logs the state after each.
    static func qaSwipe(_ store: BrowserStore) {
        Task {
            if store.spaces.count < 2 {
                store.commit(SpaceDraft(name: "QA", hue: 0.6, symbol: "star", profile: .existing(store.spaces[0].profile.id)))
            }
            store.switchTo(store.spaces[0])
            for (label, steps, interval) in [("slow past half", 12, 0.04), ("flick", 4, 0.01), ("short", 3, 0.05)] {
                try? await Task.sleep(for: .seconds(1))
                let forward = store.activeSpace === store.spaces[0]
                let start = ProcessInfo.processInfo.systemUptime
                store.spaceSwipeTravel = 0
                store.spaceSwipeSamples = []
                var travel: CGFloat = 0
                for step in 1...steps {
                    travel = CGFloat(step) * 12 * (forward ? 1 : -1)
                    store.trackSpaceSwipe(to: travel, at: start + Double(step) * interval)
                }
                store.spaceSwipeTravel = nil
                store.finishSpaceSwipe(travel: travel, at: start + Double(steps) * interval, switches: true)
                try? await Task.sleep(for: .seconds(1))
                log("QA \(label): active \(store.activeSpace.name) pager \(store.pagerSpaces.map(\.name)) offset \(store.spaceSwipeOffset)")
            }
        }
    }
}
#endif
