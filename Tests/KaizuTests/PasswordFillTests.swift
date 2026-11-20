import Testing
import WebKit
@testable import Kaizu

/// password-fill.js finds login fields and fills the one Kaizu's picker
/// was opened for. Run against the real script in its own world, on local
/// pages with an https origin (no network).
@MainActor
struct PasswordFillTests {
    private static let form = """
        <form>
          <input id=search type=search>
          <input id=user name=login>
          <input id=pass type=password>
        </form>
        """

    @Test func reportsLoginFieldsOnly() async throws {
        let page = try await Page(Self.form)
        try await page.run("document.getElementById('user').focus()")
        try await page.run("document.getElementById('pass').focus()")
        try await page.run("document.getElementById('search').focus()")
        let messages = try await page.messages(count: 4)
        // Leaving a login field says so; focusing a search field adds nothing.
        #expect(messages.map { $0["type"] as? String } == ["focus", "blur", "focus", "blur"])
        #expect(messages.map { $0["password"] as? Bool } == [false, nil, true, nil])
        #expect((messages.first?["width"] as? NSNumber)?.doubleValue ?? 0 > 0)
    }

    @Test func fillsBothFieldsAsTheUsersEdit() async throws {
        let page = try await Page(Self.form + """
            <script>
            // Like React: the page keeps its own copy of the value, set through
            // the element, and only an input whose value differs counts.
            window.seen = [];
            for (const field of document.querySelectorAll('input')) {
              let kept = '';
              const native = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
              Object.defineProperty(field, 'value', {
                get() { return native.get.call(this); },
                set(value) { kept = value; native.set.call(this, value); },
              });
              field.addEventListener('input', () => {
                if (native.get.call(field) !== kept) seen.push(field.id);
                kept = native.get.call(field);
              });
            }
            </script>
            """)
        try await page.run("document.getElementById('user').focus()")
        #expect(try await page.fill("ada", "secret") == "both")
        #expect(try await page.value(of: "user") == "ada")
        #expect(try await page.value(of: "pass") == "secret")
        #expect(try await page.run("return seen") as? [String] == ["user", "pass"])
        // The cursor ends up where the user goes on: the password.
        #expect(try await page.run("return document.activeElement.id") as? String == "pass")
    }

    @Test func fromThePasswordFieldFillsTheUsernameBeforeIt() async throws {
        let page = try await Page(Self.form)
        try await page.run("document.getElementById('pass').focus()")
        #expect(try await page.fill("ada", "secret") == "both")
        #expect(try await page.value(of: "user") == "ada")
        #expect(try await page.value(of: "search") == "")
    }

    @Test func usernameFirstPagesGetTheUsername() async throws {
        let page = try await Page("<input id=email type=email autocomplete=username>")
        try await page.run("document.getElementById('email').focus()")
        #expect(try await page.fill("ada@example.com", "secret") == "username")
        #expect(try await page.value(of: "email") == "ada@example.com")
    }

    @Test func refusesAnotherOrigin() async throws {
        let page = try await Page(Self.form)
        try await page.run("document.getElementById('user').focus()")
        #expect(try await page.fill("ada", "secret", origin: "https://evil.example") == "origin")
        #expect(try await page.value(of: "user") == "")
        #expect(try await page.value(of: "pass") == "")
    }

    @Test func theMenuStartsAtTheLoginFormsFirstField() async throws {
        // A newsletter sign-up before the login form is passed over.
        let page = try await Page("<input id=news type=email>" + Self.form)
        #expect(try await page.view.callAsyncJavaScript("return __kaizuFocusLogin()", contentWorld: PasswordFill.world) as? Bool == true)
        #expect(try await page.run("return document.activeElement.id") as? String == "user")
    }

    @Test func leavesSignUpPasswordsAlone() async throws {
        let page = try await Page("<form><input id=new type=password autocomplete=new-password></form>")
        #expect(try await page.fill("ada", "secret") == "none")
        #expect(try await page.value(of: "new") == "")
    }

    @Test func pagesCantReachTheFiller() async throws {
        let page = try await Page(Self.form)
        let reach = try await page.view.callAsyncJavaScript(
            "return typeof globalThis.__kaizuFillLogin + typeof window.webkit?.messageHandlers?.kaizuPasswords",
            contentWorld: .page) as? String
        #expect(reach == "undefinedundefined")
    }

    @Test func autoFillIsTellingFromTyping() {
        typealias Entry = PasswordPicker.Entry
        // macOS fills both at once.
        #expect(PasswordPicker.looksAutoFilled(from: Entry(username: "", password: ""), to: Entry(username: "ada", password: "secret")))
        #expect(PasswordPicker.looksAutoFilled(from: Entry(username: "a", password: ""), to: Entry(username: "ada", password: "secret")))
        // Typing: the username first, then the password a key at a time.
        #expect(!PasswordPicker.looksAutoFilled(from: Entry(username: "ada", password: ""), to: Entry(username: "ada", password: "s")))
        #expect(!PasswordPicker.looksAutoFilled(from: Entry(username: "ada", password: "s"), to: Entry(username: "ada", password: "se")))
        #expect(!PasswordPicker.looksAutoFilled(from: Entry(username: "", password: ""), to: Entry(username: "", password: "secret")))
    }
}

/// A page with the script in its world, as an https origin.
@MainActor
private final class Page: NSObject, WKScriptMessageHandler {
    static let origin = "https://login.example.com"
    let view: WKWebView
    private let window: NSWindow
    private(set) var received: [[String: Any]] = []

    init(_ body: String) async throws {
        let script = try #require(PasswordFill.script)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.addUserScript(script)
        view = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: config)
        // Focus moves only in a page that has it, which takes a window.
        window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 400, height: 300),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        super.init()
        config.userContentController.add(self, contentWorld: PasswordFill.world, name: PasswordFill.handlerName)
        window.orderFrontRegardless()
        window.makeFirstResponder(view)
        view.loadHTMLString("<!doctype html><title>t</title><body>\(body)</body>", baseURL: URL(string: Self.origin + "/signin"))
        for _ in 0..<100 {
            if (try? await view.evaluateJavaScript("location.origin === '\(Self.origin)' && document.readyState === 'complete'") as? Bool) == true {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("The page didn't load")
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: Any] { received.append(body) }
    }

    @discardableResult
    func run(_ body: String) async throws -> Any? {
        try await view.callAsyncJavaScript(body, contentWorld: .page)
    }

    func value(of id: String) async throws -> String? {
        try await run("return document.getElementById('\(id)').value") as? String
    }

    func fill(_ username: String, _ password: String, origin: String = Page.origin) async throws -> String? {
        try await view.callAsyncJavaScript(
            "return __kaizuFillLogin(username, password, origin)",
            arguments: ["username": username, "password": password, "origin": origin],
            contentWorld: PasswordFill.world) as? String
    }

    /// What the script has posted, once `count` messages are in or a second has gone by.
    func messages(count: Int) async throws -> [[String: Any]] {
        for _ in 0..<20 where received.count < count {
            try await Task.sleep(for: .milliseconds(50))
        }
        return received
    }
}
