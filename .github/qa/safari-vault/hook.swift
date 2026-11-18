        case "safari-vault-acceptance":
            Task {
                guard ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted" else { exit(2) }
                let env = ProcessInfo.processInfo.environment
                let root = URL(fileURLWithPath: env["RUNNER_TEMP"]!).appending(path: "vault-test")
                let app = URL(fileURLWithPath: env["KAIZU_EXTENSION"]!)
                let pass = try! String(contentsOf: root.appending(path: "dummy-pass"), encoding: .utf8)
                let flow = try! String(contentsOf: Bundle.main.url(forResource: "VaultQA", withExtension: "js")!, encoding: .utf8)
                await store.extensions.install(from: app, askFirst: false)
                guard let item = store.extensions.installed.first else { print("No installed extension"); exit(3) }
                print("Installed Safari extension", item.name, item.version)
                @MainActor func webview(_ root: NSView) -> WKWebView? {
                    if let web = root as? WKWebView { return web }
                    for child in root.subviews { if let web = webview(child) { return web } }
                    return nil
                }
                @MainActor func openPopup(_ tab: BrowserTab) async -> WKWebView? {
                    store.extensions.performAction(for: item, on: tab, anchor: CGRect(x: 40, y: 40, width: 20, height: 20))
                    for _ in 0..<70 {
                        if let view = store.extensions.action(for: item, on: tab)?.popupPopover?.contentViewController?.view,
                           let web = webview(view), web.url?.scheme == "webkit-extension", !web.isLoading,
                           (try? await web.evaluateJavaScript("document.readyState === 'complete' && !!document.body?.innerText.trim()")) as? Bool == true {
                            return web
                        }
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                    return nil
                }
                let tab = store.openTab(URL(string: "https://127.0.0.1:18764/login")!)
                try? await Task.sleep(for: .seconds(3))
                guard let popup = await openPopup(tab) else { print("No Bitwarden popup"); exit(4) }
                var failure: String?
                Task {
                    do {
                        _ = try await popup.callAsyncJavaScript(flow, arguments: ["password":pass], in:nil, contentWorld:.page)
                    } catch {
                        let error = error as NSError
                        failure = error.userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
                    }
                }
                var filled = false
                for _ in 0..<200 {
                    let check = try? await tab.webView.evaluateJavaScript("""
                        document.querySelector('[name=username]')?.value === 'synthetic-kaizu-user' &&
                        document.querySelector('[name=password]')?.value === 'Kaizu-QA-Field-Only-42!'
                        """)
                    if check as? Bool == true { filled = true; break }
                    if let failure {
                        print("Bitwarden UI:", failure)
                        let state = try? await popup.evaluateJavaScript("[document.title, document.body.innerText.slice(0,400)]")
                        print("Popup after failure:", String(describing:state), item.context.errors.map(\.localizedDescription))
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                }
                guard filled else { print("Matching login did not fill."); exit(5) }
                print("The original Safari extension filled the matching site's synthetic login.")
                let unrelated = store.openTab(URL(string: "https://localhost:18764/login")!)
                try? await Task.sleep(for: .seconds(2))
                guard let otherPopup = await openPopup(unrelated) else { print("No popup on unrelated site"); exit(6) }
                let negative = try? await otherPopup.callAsyncJavaScript("""
                    const wait = ms => new Promise(r => setTimeout(r,ms));
                    for (let i=0; i<50; i++) {
                        const text = document.body.innerText;
                        if (/no (matching|autofill suggestions)|no items to autofill/i.test(text)) return true;
                        await wait(200);
                    }
                    return document.body.innerText.slice(0,500);
                    """, arguments:[:], in:nil, contentWorld:.page)
                let empty = try? await unrelated.webView.evaluateJavaScript("""
                    document.querySelector('[name=username]')?.value === '' && document.querySelector('[name=password]')?.value === ''
                    """)
                guard negative as? Bool == true, empty as? Bool == true else {
                    print("Unrelated-site check inconclusive:", String(describing: negative)); exit(7)
                }
                print("No matching suggestion or filled fields on the unrelated site.")
                NSApp.terminate(nil)
            }
