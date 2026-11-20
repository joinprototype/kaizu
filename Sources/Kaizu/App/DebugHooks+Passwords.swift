#if DEBUG
import AppKit
import BrowserCore
import WebKit

extension DebugHooks {
    /// `passwords`: opens KAIZU_URL (a login page), clicks into its first
    /// login field, checks the key shows and Fill from Passwords opens the
    /// picker, then fills a made-up login as a picked one would and logs
    /// what the page's fields hold. Logs each rule as ok or FAILED and quits.
    static func qaPasswords(_ store: BrowserStore) {
        guard let url = ProcessInfo.processInfo.environment["KAIZU_URL"].flatMap(URL.init(string:)) else { return }
        let tab = store.openTab(url)
        Task {
            func check(_ name: String, _ passed: Bool) {
                log("QA passwords \(passed ? "ok" : "FAILED"): \(name)")
            }
            await loaded(tab)
            guard let fill = tab.passwordFill else {
                check("the tab has a filler", false)
                NSApp.terminate(nil)
                return
            }
            _ = try? await tab.webView.evaluateJavaScript("globalThis.__kaizuFocusLogin?.()", in: nil, contentWorld: PasswordFill.world)
            check("the key shows on the focused field", await until(3) { fill.isKeyShown })
            if let shot = ProcessInfo.processInfo.environment["KAIZU_SHOT"] {
                saveShot(of: store.window, to: shot.replacingOccurrences(of: ".png", with: "-key.png"))
            }
            fill.openFromMenu()
            check("Fill from Passwords opens the picker", await until(3) { fill.isPickerShown })
            fill.fillForQA(username: "kaizu-qa", password: "not-a-real-password")
            let filled = await until(3) {
                let values = try? await tab.webView.callAsyncJavaScript(
                    "return [...document.querySelectorAll('input')].map(i => i.value).filter(Boolean)",
                    contentWorld: .page) as? [String]
                return values?.contains("kaizu-qa") == true && values?.contains("not-a-real-password") == true
            }
            check("the page's fields hold the login", filled)
            // Closing animates: the popover says it's shown until it's gone.
            check("the picker closed", await until(2) { !fill.isPickerShown })
            NSApp.terminate(nil)
        }
    }
}
#endif
