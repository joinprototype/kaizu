import AppKit

/// The picker behind the key on a login field: a real username and
/// password field, where macOS offers "Passwords…" and fills in the login
/// the user picks after Touch ID. A login macOS fills in goes to the page
/// at once; one typed by hand goes with Fill. Either way the fields are
/// emptied the moment it's handed over, and when the picker closes.
final class PasswordPicker: NSViewController {
    private let host: String
    private let isSecure: Bool
    private let onFill: (_ username: String, _ password: String) -> Void
    private let username = NSTextField()
    private let password = NSSecureTextField()
    private let fillButton = NSButton(title: "Fill", target: nil, action: nil)
    private var watch: Timer?
    private var before = Entry(username: "", password: "")
    /// Closes whatever shows the picker.
    var onCancel: (() -> Void)?

    /// What the two fields hold.
    struct Entry: Equatable {
        var username: String
        var password: String
    }

    init(host: String, isSecure: Bool, onFill: @escaping (_ username: String, _ password: String) -> Void) {
        self.host = host
        self.isSecure = isSecure
        self.onFill = onFill
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    nonisolated required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// macOS fills both fields at once; a person types into one at a time.
    /// So a password and a new username arriving together, onto an empty
    /// password, is AutoFill's doing.
    nonisolated static func looksAutoFilled(from before: Entry, to after: Entry) -> Bool {
        before.password.isEmpty && !after.password.isEmpty && !after.username.isEmpty
            && after.username != before.username
    }

    override func loadView() {
        let title = NSTextField(labelWithString: "")
        let line = NSMutableAttributedString(string: "Fill a login on ", attributes: [.font: NSFont.systemFont(ofSize: 13)])
        line.append(NSAttributedString(string: host, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]))
        title.attributedStringValue = line
        title.lineBreakMode = .byTruncatingMiddle

        username.placeholderString = "Username"
        username.contentType = .username
        password.placeholderString = "Password"
        password.contentType = .password
        for field in [username, password] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 260).isActive = true
        }

        let hint = NSTextField(wrappingLabelWithString: isSecure
            ? "Click Username, then choose Passwords… to pick a saved login."
            : "This page isn’t secure, so others on the network could see what you send.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = isSecure ? .secondaryLabelColor : .systemOrange
        hint.preferredMaxLayoutWidth = 260

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        fillButton.target = self
        fillButton.action = #selector(fill)
        fillButton.keyEquivalent = "\r"
        fillButton.isEnabled = false
        let buttons = NSStackView(views: [NSView(), cancel, fillButton])
        buttons.orientation = .horizontal

        let stack = NSStackView(views: [title, username, password, hint, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 12, right: 14)
        buttons.widthAnchor.constraint(equalTo: username.widthAnchor).isActive = true
        view = stack
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Focus in the username field is what brings up "Passwords…".
        view.window?.makeFirstResponder(username)
        // AutoFill sets the fields without telling their delegates, so look.
        let watch = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(watch, forMode: .common)
        self.watch = watch
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        watch?.invalidate()
        watch = nil
        clear()
    }

    private var entry: Entry {
        // A field being edited holds its text in the field editor.
        func text(_ field: NSTextField) -> String {
            (field.currentEditor() as? NSTextView)?.string ?? field.stringValue
        }
        return Entry(username: text(username), password: text(password))
    }

    private func check() {
        let now = entry
        defer { before = now }
        fillButton.isEnabled = !now.password.isEmpty || !now.username.isEmpty
        if Self.looksAutoFilled(from: before, to: now) {
            hand(now)
        }
    }

    @objc private func fill() {
        let now = entry
        guard !now.password.isEmpty || !now.username.isEmpty else { return }
        hand(now)
    }

    @objc private func cancel() {
        clear()
        onCancel?()
    }

    private func hand(_ login: Entry) {
        watch?.invalidate()
        watch = nil
        clear()
        onFill(login.username, login.password)
    }

    private func clear() {
        view.window?.makeFirstResponder(nil)
        username.stringValue = ""
        password.stringValue = ""
        before = Entry(username: "", password: "")
    }
}
