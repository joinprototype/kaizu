#if DEBUG
import AppKit
import Storage
import WebKit

extension DebugHooks {
    static func qaNotificationRouting(_ store: BrowserStore) async {
        precondition(ProcessInfo.processInfo.environment["KAIZU_SUPPORT"] != nil)
        let app = store.app
        let address = URL(string: "https://example.org/work-notification")!
        let file = AppPaths.support.appending(path: "notification-qa.plist")
        if ProcessInfo.processInfo.environment["KAIZU_DEBUG"] == "notification-routing-restored" {
            let info = try! PropertyListDecoder().decode([String: String].self, from: Data(contentsOf: file))
            let destination = SiteNotificationDestination(userInfo: info)
            let work = app.spaces.first { $0.id == destination.spaceID }!
            let personal = app.spaces.first { $0.profile !== work.profile }!
            store.switchTo(personal)
            app.openNotification(destination)
            let reopened = work.today.first { $0.url == address }!
            precondition(reopened.profile.id == destination.profileID && app.front.selectedTab === reopened)
            precondition(personal.today.isEmpty)

            // Navigating away after posting keeps the newer page intact on click.
            let previous = SiteNotificationDestination(tab: reopened, page: "previous", url: address)
            let elsewhere = URL(string: "https://example.org/next")!
            reopened.load(elsewhere)
            app.openNotification(previous)
            precondition(reopened.url == elsewhere && app.front.selectedTab !== reopened)
            precondition(app.front.selectedTab?.url == address)

            // A removed profile cannot redirect old notices to the remaining profile.
            store.delete(work)
            precondition(!app.profiles.contains { $0 === work.profile })
            app.openNotification(destination)
            precondition(personal.today.isEmpty)
        } else {
            let workProfile = Profile(name: "Work")
            let workSpace = Space(profile: workProfile, name: "Work", symbol: "briefcase", hue: 0.4)
            app.profiles.append(workProfile)
            app.spaces.append(workSpace)
            let work = app.openWindow(on: workSpace)
            let tab = work.openTab(nil)
            var posted: SiteNotificationDestination?
            SiteNotifications.onDeliver = { _, destination in posted = destination }
            app.settings.setPermission(SiteNotifications.permission, to: true, on: address.host()!)
            tab.webView.loadSimulatedRequest(URLRequest(url: address), responseHTML: """
                <!doctype html><title>Notification routing</title><script>
                window.fixtureStarted = true;
                const message = new Notification("A work message");
                message.onshow = () => window.shown = true;
                message.onclick = () => window.clicked = true;
                </script>
                """)
            // The first HTTPS navigation can wait for cold content rules before WebKit runs the page.
            // Give delivery its own deadline once the fixture has actually started.
            await withCheckedContinuation { continuation in
                app.contentBlocker.whenReady(for: address) { continuation.resume() }
            }
            await waitForPageFlag("fixtureStarted", on: tab)
            await waitForPageFlag("shown", on: tab)
            let destination = posted!
            precondition(destination.url == address && destination.tabID == tab.id)
            precondition(destination.spaceID == workSpace.id && destination.profileID == workProfile.id)
            try! PropertyListEncoder().encode(destination.userInfo).write(to: file)
            app.front = store
            app.openNotification(destination)
            precondition(app.front.selectedTab === tab && workSpace.today.count == 1)
            await waitForPageFlag("clicked", on: tab)
            SiteNotifications.onDeliver = nil
            work.close(tab)
            app.front = store
            // A notification delivered by an earlier version has no profile or space.
            let legacy = destination.userInfo.filter { $0.key != "space" && $0.key != "profile" }
            app.openNotification(SiteNotificationDestination(userInfo: legacy))
            let reopened = workSpace.today.first { $0.url == address }!
            precondition(store.activeSpace.today.isEmpty && app.front.selectedTab === reopened)
            work.close(reopened)
            app.front = store
            app.save()
        }
        print("Verified notification routing across Work and Personal profiles")
        NSApp.terminate(nil)
    }

    private static func waitForPageFlag(_ flag: String, on tab: BrowserTab) async {
        for _ in 0..<100 {
            if (try? await tab.webView.evaluateJavaScript("window." + flag)) as? Bool == true { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        preconditionFailure("The notification page did not report " + flag)
    }
}
#endif
