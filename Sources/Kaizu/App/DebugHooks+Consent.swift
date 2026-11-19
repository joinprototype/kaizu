#if DEBUG
import AppKit
import WebKit

extension DebugHooks {
    /// KAIZU_DEBUG=consent: opens each of KAIZU_SITES (comma separated; by
    /// default the consent platforms in the roadmap) in a private window, so
    /// every run starts without consent cookies and leaves none behind, and
    /// logs what the site's consent platform recorded, what autoconsent did,
    /// and what the app sent to the page's frames. Waits up to
    /// KAIZU_SITE_WAIT seconds (12) per site, KAIZU_SHOTS saves a picture of
    /// each, then quits.
    static func qaConsent(_ store: BrowserStore) {
        precondition(ProcessInfo.processInfo.environment["KAIZU_SUPPORT"] != nil)
        let environment = ProcessInfo.processInfo.environment
        let defaults = "https://www.cookiebot.com/en/help/,https://www.cookieyes.com/documentation/retrieving-consent-data-using-api-getckyconsent/,https://sandbox.didomi.io/cmp.html"
        let sites = (environment["KAIZU_SITES"] ?? defaults).split(separator: ",").compactMap { URL(string: String($0)) }
        let wait = environment["KAIZU_SITE_WAIT"].flatMap(Double.init) ?? 12
        func log(_ text: String) {
            FileHandle.standardError.write(Data("QA consent \(text)\n".utf8))
        }
        // In the page's world: what each platform's own API says.
        let platform = """
            (() => {
              const safely = (read) => { try { return read(); } catch (e) { return 'error: ' + e.message; } };
              const state = {};
              if (window.Cookiebot) state.cookiebot = safely(() => ({ hasResponse: Cookiebot.hasResponse, declined: Cookiebot.declined,
                necessary: Cookiebot.consent?.necessary, preferences: Cookiebot.consent?.preferences,
                statistics: Cookiebot.consent?.statistics, marketing: Cookiebot.consent?.marketing }));
              if (typeof getCkyConsent === 'function') state.cookieyes = safely(() => {
                const consent = getCkyConsent();
                return { isUserActionCompleted: consent.isUserActionCompleted, categories: consent.categories };
              });
              if (window.Didomi) state.didomi = safely(() => ({ noticeVisible: Didomi.notice?.isVisible?.(),
                shouldConsentBeCollected: Didomi.shouldConsentBeCollected?.(),
                purposes: Object.fromEntries(Object.entries(Didomi.getCurrentUserStatus?.()?.purposes ?? {}).map(([id, p]) => [id, p.enabled])) }));
              // Autoconsent should leave no trace in the page's world.
              state.pageSees = [typeof window.kaizuAutoconsent, typeof window.webkit].join('/');
              return JSON.stringify(state);
            })()
            """
        // In autoconsent's world: what it reported about this page.
        let messages = """
            JSON.stringify((window.kaizuAutoconsent?.messages ?? [])
              .filter(m => ['cmpDetected', 'popupFound', 'optOutResult', 'autoconsentDone', 'autoconsentError'].includes(m.type))
              .map(m => m.type + (m.cmp ? ':' + m.cmp : '') + (m.result !== undefined ? '=' + m.result : '')))
            """
        log("rejection \(store.contentBlocker.isCookieRejectionEnabled ? "on" : "OFF"), blocking \(store.contentBlocker.isEnabled ? "on" : "off")")
        let window = store.app.openPrivateWindow()
        Task {
            for url in sites {
                let frames = AutoconsentBridge.framesServed, main = AutoconsentBridge.mainFramesServed
                let bytes = AutoconsentBridge.bytesServed, evaluations = AutoconsentBridge.evaluations
                let tab = window.openTab(url)
                let start = ContinuousClock.now
                try? await Task.sleep(for: .seconds(1))
                while tab.isLoading, ContinuousClock.now - start < .seconds(20) {
                    try? await Task.sleep(for: .milliseconds(250))
                }
                let loaded = start.duration(to: .now)
                var state = "{}", done = "[]"
                while ContinuousClock.now - start < loaded + .seconds(wait) {
                    try? await Task.sleep(for: .seconds(1))
                    state = (try? await tab.webView.evaluateJavaScript(platform)) as? String ?? "{}"
                    done = (try? await tab.webView.evaluateJavaScript(messages, contentWorld: AutoconsentBridge.world)) as? String ?? "[]"
                    if done.contains("autoconsentDone") || done.contains("optOutResult=false") || done.contains("autoconsentError") { break }
                }
                // Let the platform store the choice before reading it.
                try? await Task.sleep(for: .seconds(1.5))
                state = (try? await tab.webView.evaluateJavaScript(platform)) as? String ?? "{}"
                log("\(url.host() ?? "site") | loaded in \(loaded.components.seconds) s | platform \(state) | autoconsent \(done)")
                log("\(url.host() ?? "site") | sent \(AutoconsentBridge.framesServed - frames) frames (\(AutoconsentBridge.mainFramesServed - main) main) \(AutoconsentBridge.bytesServed - bytes) B of rules, ran \(AutoconsentBridge.evaluations - evaluations) page checks")
                if let folder = environment["KAIZU_SHOTS"], let image = await tab.screenshot(of: nil), let data = image.tiffRepresentation {
                    let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
                    try? png?.write(to: URL(fileURLWithPath: folder).appending(path: "consent-\(url.host() ?? "site").png"))
                }
                window.close(tab)
            }
            NSApp.terminate(nil)
        }
    }
}
#endif
