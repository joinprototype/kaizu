import AppKit
import CoreSpotlight

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let app = AppModel()
    private lazy var notificationClicks = NotificationClicks(app: app)

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Kaizu's windows are spaces and tabs, never system tabs of each other.
        NSWindow.allowsAutomaticWindowTabbing = false
        Typeface.register()
        // Web views leave this off, unlike Safari. Registered, so turning it
        // off in the Edit menu sticks.
        UserDefaults.standard.register(defaults: ["WebContinuousSpellCheckingEnabled": true])
        // Before launch finishes: a click can be what launched Kaizu.
        SiteNotifications.center?.delegate = notificationClicks
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.notice("Kaizu \(Diagnostics.appVersion, privacy: .public) on \(Diagnostics.macOSVersion, privacy: .public)")
        Diagnostics.shared.start()
        NSApp.mainMenu = MainMenu.make(app: app)
        app.showFront()
        NSApp.activate()
        app.applyQuickBarKey()
        Updates.start(app: app)
        Task { [app] in
            // After the window's first tab, which matters more.
            try? await Task.sleep(for: .seconds(3))
            app.wakeTabsThatNotify()
        }
        #if DEBUG
        DebugHooks.apply(to: app.front)
        #endif
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        for tab in app.stores.flatMap(\.shownTabs) {
            tab.markNotificationsRead()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // A private window on screen doesn't count: the ordinary one comes back.
        if !app.stores.contains(where: { $0.window?.isVisible == true }) {
            app.front = app.regularFront
            app.showFront()
        }
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
