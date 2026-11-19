#if DEBUG
import AppKit
import BrowserCore
import CoreSpotlight

extension DebugHooks {
    /// `spotlight`: pins KAIZU_URL's tab, saves (which indexes it), then opens
    /// it again as Spotlight would and logs what got selected.
    static func qaSpotlight(_ store: BrowserStore) {
        guard let url = ProcessInfo.processInfo.environment["KAIZU_URL"].flatMap(URL.init(string:)) else { return }
        let tab = store.openTab(url)
        store.togglePin(tab)
        store.app.updateSpotlight()
        store.select(store.openTab(nil))
        store.app.openSpotlightItem(tab.id.uuidString)
        log("QA spotlight indexed \(store.app.spotlightIdentifiers.count) selected pinned \(store.selectedTab === tab)")
    }

    /// `spotlightreset`: removes everything this copy of the app put in Spotlight.
    static func clearSpotlight() {
        CSSearchableIndex.default().deleteAllSearchableItems { error in
            log("QA spotlight cleared \(error == nil)")
        }
    }

    /// `hotkeys`: which quick bar shortcuts this Mac lets us have.
    static func qaHotKeys(_ store: BrowserStore) {
        for key in Settings.QuickBarKey.allCases {
            store.settings.quickBarKey = key
            store.app.applyQuickBarKey()
            log("QA hotkey \(key.title): \(store.app.isQuickBarKeyTaken ? "taken" : "free")")
        }
        store.settings.quickBarKey = nil
        store.app.applyQuickBarKey()
        // ⌘Space is Spotlight's: must come back taken.
        let spotlight = GlobalHotKey(keyCode: 49, modifiers: 256) {}
        log("QA hotkey ⌘Space: \(spotlight == nil ? "taken" : "free")")
    }
}
#endif
