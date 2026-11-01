import AppKit
import CoreSpotlight

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let app = AppModel()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Kaizu's windows are spaces and tabs, never system tabs of each other.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.notice("Kaizu \(Diagnostics.appVersion, privacy: .public) on \(Diagnostics.macOSVersion, privacy: .public)")
        Diagnostics.shared.start()
        NSApp.mainMenu = MainMenu.make(app: app)
        app.showFront()
        NSApp.activate()
        app.applyQuickBarKey()
        Updates.start(app: app)
        #if DEBUG
        DebugHooks.apply(to: app.front)
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { app.showFront() }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.app.notice("Quitting")
        app.save()
        app.updateSpotlight()
        app.saveTabStates()
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
        app.openSpotlightItem(identifier)
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let store = app.regularFront
        let showsMainWindow = urls.map(store.openExternal).contains(true)
        // Also on launch from a link, before the windows exist.
        if showsMainWindow || store.windowController == nil {
            app.showFront()
        }
    }
}
