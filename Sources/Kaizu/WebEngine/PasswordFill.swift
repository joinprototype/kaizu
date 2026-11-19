import AppKit
import DesignSystem
import WebKit

/// Fills logins from the Passwords app (iCloud Keychain).
///
/// Kaizu can't read the Passwords app, and Apple's extension for other
/// browsers only answers the browsers on Apple's list. What every Mac app
/// gets is AutoFill in its own login fields: macOS offers "Passwords…"
/// there and, after Touch ID, fills in the login the user picks. So Kaizu
/// shows a key on a page's focused login field. The key opens a picker
/// holding a pair of real login fields, and whatever macOS fills into them
/// goes to `password-fill.js` for the page's form, then is forgotten.
///
/// The script lives in its own content world, so pages can neither call it
/// nor post to this handler. A login only goes to the frame whose field
/// opened the picker, and only while that frame is on the same origin.
final class PasswordFill: NSObject, WKScriptMessageHandler, NSPopoverDelegate {
    static let world = WKContentWorld.world(name: "KaizuPasswords")
    static let handlerName = "kaizuPasswords"
    /// How long a username-first page's password waits for the next page.
    static let heldFor: Duration = .seconds(120)

    /// Every frame: sign-in forms often live in one. Part of the content
    /// blocker's standard scripts, which it puts back whenever it replaces them.
    static let script: WKUserScript? = {
        guard let url = BundledResource.url(named: "password-fill", extension: "js", in: "Scripts"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: world)
    }()

    /// The login field that last had focus.
    struct Field {
        let frame: WKFrameInfo
        /// In CSS pixels, in its frame's viewport.
        let rect: CGRect
        let isPassword: Bool
    }

    private weak var tab: BrowserTab?
    private(set) var field: Field?
    private var key: KeyButton?
    private var hiding: Task<Void, Never>?
    private var picker: NSPopover?
    private var opensWhenFocused = false
    /// A username-first page's password, for the same origin's password page.
    private var held: (origin: String, password: String, until: ContinuousClock.Instant)?

    static func install(on controller: WKUserContentController, for tab: BrowserTab) -> PasswordFill {
        let handler = PasswordFill()
        handler.tab = tab
        controller.add(handler, contentWorld: world, name: handlerName)
        return handler
    }

    /// "https://example.com", as the page's `location.origin` puts it.
    /// Nil for anything but the web.
    static func origin(of origin: WKSecurityOrigin) -> String? {
        guard ["http", "https"].contains(origin.protocol), !origin.host.isEmpty else { return nil }
        return "\(origin.protocol)://\(origin.host)" + (origin.port == 0 ? "" : ":\(origin.port)")
    }

    // MARK: - From the page

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let tab, tab.isLoaded, let webView = message.webView, webView === tab.webView,
              let body = message.body as? [String: Any], let type = body["type"] as? String,
              Self.origin(of: message.frameInfo.securityOrigin) != nil
        else { return }
        switch type {
        case "focus":
            let numbers = ["x", "y", "width", "height"].compactMap { (body[$0] as? NSNumber)?.doubleValue }
            guard numbers.count == 4, numbers.allSatisfy(\.isFinite), numbers[2] > 0, numbers[3] > 0 else { return }
            hiding?.cancel()
            field = Field(
                frame: message.frameInfo,
                rect: CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]),
                isPassword: body["password"] as? Bool == true
            )
            if opensWhenFocused {
                opensWhenFocused = false
                openPicker()
            } else if picker == nil {
                showKey(in: webView)
            }
        case "blur":
            // Not at once: the field may only be moving (a scroll, a re-render).
            hiding?.cancel()
            hiding = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                self?.hideKey()
            }
        default:
            break
        }
    }

    // MARK: - Key

    /// Over the right end of a main-frame field. A subframe's field has no
    /// key (its place in the page is out of reach); the menu command works there.
    private func showKey(in webView: WKWebView) {
        guard let field, field.frame.isMainFrame else {
            hideKey()
            return
        }
        let zoom = webView.pageZoom
        let side: CGFloat = 20
        let fieldFrame = CGRect(
            x: field.rect.minX * zoom, y: field.rect.minY * zoom,
            width: field.rect.width * zoom, height: field.rect.height * zoom
        )
        var frame = CGRect(x: fieldFrame.maxX - side - 6, y: fieldFrame.midY - side / 2, width: side, height: side)
        if !webView.isFlipped {
            frame.origin.y = webView.bounds.height - frame.maxY
        }
        guard webView.bounds.contains(frame) else {
            hideKey()
            return
        }
        let key = self.key ?? KeyButton { [weak self] in self?.keyPressed() }
        self.key = key
        key.frame = frame
        if key.superview !== webView {
            webView.addSubview(key)
        }
    }

    private func hideKey() {
        key?.removeFromSuperview()
    }

    private func keyPressed() {
        openPicker()
    }

    // MARK: - Picker

    /// Edit ▸ Fill from Passwords: for the field that has focus, or the page's
    /// first login field.
    func openFromMenu() {
        guard let tab, tab.isLoaded else { return }
        opensWhenFocused = true
        tab.webView.evaluateJavaScript("globalThis.__kaizuFocusLogin?.() ?? false", in: nil, in: Self.world) { [weak self] result in
            guard case .success(let found) = result, found as? Bool == true else {
                self?.opensWhenFocused = false
                tab.store?.showToast("No login fields on this page", symbol: "key")
                return
            }
            // The field reports its focus right away; one that doesn't
            // mustn't leave a picker waiting for the next field focused.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.opensWhenFocused = false
            }
        }
    }

    private func openPicker() {
        guard let tab, tab.isLoaded, picker == nil, let field,
              let origin = Self.origin(of: field.frame.securityOrigin)
        else { return }
        let webView = tab.webView
        // The second page of a username-first sign-in: the password picked
        // on the first, without asking again.
        if field.isPassword, let held, held.origin == origin, ContinuousClock.now < held.until {
            self.held = nil
            fill(username: "", password: held.password, origin: origin, in: field.frame)
            return
        }
        held = nil
        let host = field.frame.securityOrigin.host
        let controller = PasswordPicker(host: host, isSecure: field.frame.securityOrigin.protocol == "https") { [weak self] username, password in
            self?.picker?.close()
            self?.fill(username: username, password: password, origin: origin, in: field.frame)
        }
        let popover = NSPopover()
        controller.onCancel = { [weak popover] in popover?.close() }
        popover.contentViewController = controller
        // Not transient: macOS's own Passwords panel takes the app's focus,
        // which would close a transient popover, and its fields with it.
        popover.behavior = .semitransient
        popover.delegate = self
        picker = popover
        hideKey()
        popover.show(relativeTo: anchor(for: field, in: webView), of: webView, preferredEdge: .maxY)
    }

    /// The field itself in the main frame; in a subframe, where the pointer is.
    private func anchor(for field: Field, in webView: WKWebView) -> CGRect {
        if field.frame.isMainFrame {
            let zoom = webView.pageZoom
            var rect = CGRect(x: field.rect.minX * zoom, y: field.rect.minY * zoom,
                              width: field.rect.width * zoom, height: field.rect.height * zoom)
            if !webView.isFlipped {
                rect.origin.y = webView.bounds.height - rect.maxY
            }
            let visible = rect.intersection(webView.bounds)
            if !visible.isEmpty { return visible }
        }
        let pointer = webView.window.map { webView.convert($0.mouseLocationOutsideOfEventStream, from: nil) }
        if let pointer, webView.bounds.contains(pointer) {
            return CGRect(origin: pointer, size: CGSize(width: 1, height: 1))
        }
        return CGRect(x: webView.bounds.midX, y: webView.bounds.midY, width: 1, height: 1)
    }

    func popoverDidClose(_ notification: Notification) {
        picker = nil
    }

    #if DEBUG
    /// For the QA hook.
    var isKeyShown: Bool { key?.superview != nil }
    var isPickerShown: Bool { picker?.isShown == true }

    /// Fills as a picked login would, without the picker.
    func fillForQA(username: String, password: String) {
        guard let field, let origin = Self.origin(of: field.frame.securityOrigin) else { return }
        picker?.close()
        fill(username: username, password: password, origin: origin, in: field.frame)
    }
    #endif

    // MARK: - Fill

    private func fill(username: String, password: String, origin: String, in frame: WKFrameInfo) {
        guard let tab, tab.isLoaded else { return }
        tab.webView.callAsyncJavaScript(
            "return globalThis.__kaizuFillLogin?.(username, password, origin) ?? 'none'",
            arguments: ["username": username, "password": password, "origin": origin],
            in: frame,
            in: Self.world
        ) { [weak self, weak tab] result in
            let outcome = (try? result.get()) as? String
            switch outcome {
            case "both", "password":
                break
            case "username":
                // A username-first sign-in: the password goes on its next page.
                if !password.isEmpty {
                    self?.held = (origin, password, ContinuousClock.now + Self.heldFor)
                }
            default:
                tab?.store?.showToast("Couldn’t fill the login: the page changed", symbol: "key")
            }
        }
    }
}

/// The key on a login field. It never takes focus, so the page keeps its own.
final class KeyButton: NSButton {
    private let onPress: () -> Void

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
        super.init(frame: .zero)
        isBordered = false
        refusesFirstResponder = true
        image = NSImage(systemSymbolName: "key.fill", accessibilityDescription: "Fill from Passwords")?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        contentTintColor = .secondaryLabelColor
        toolTip = "Fill from Passwords (\(CommandRegistry.shortcut("edit.fillFromPasswords") ?? ""))"
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.92).cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 0.5
        target = self
        self.action = #selector(pressed)
    }

    @available(*, unavailable)
    nonisolated required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func pressed() {
        onPress()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}
