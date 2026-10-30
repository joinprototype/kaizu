import AppKit
import CoreSpotlight

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = BrowserStore()
    private var windowController: BrowserWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.notice("Kaizu \(Diagnostics.appVersion, privacy: .public) on \(Diagnostics.macOSVersion, privacy: .public)")
        Diagnostics.shared.start()
        NSApp.mainMenu = MainMenu.make(store: store)
        showWindow()
        NSApp.activate()
        store.applyQuickBarKey()
        Updates.start(store: store)
        #if DEBUG
        DebugHooks.apply(to: store)
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWindow() }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.app.notice("Quitting")
        store.save()
        store.saveTabStates()
        Updates.installIfReady()
    }

    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        else { return false }
        store.openSpotlightItem(identifier)
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let showsMainWindow = urls.map(store.openExternal).contains(true)
        if showsMainWindow || windowController == nil {
            showWindow()
        }
    }

    private func showWindow() {
        if windowController == nil {
            windowController = BrowserWindowController(store: store)
        }
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }
}
