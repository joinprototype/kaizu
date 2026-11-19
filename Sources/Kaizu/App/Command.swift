import AppKit

/// Something you can do from the main menu, by its shortcut or from the
/// command bar. Declared once in `CommandRegistry`; `MainMenu` builds the
/// menu bar from it, and the command bar and the Keyboard Shortcuts card
/// read it back.
struct Command: Identifiable {
    /// A key equivalent: the character AppKit matches and its modifiers.
    struct Key: Equatable {
        let character: String
        let modifiers: NSEvent.ModifierFlags

        /// "⇧⌘T", as the menus show it.
        var label: String {
            Self.label(character: character, modifiers: modifiers)
        }

        static func label(character: String, modifiers: NSEvent.ModifierFlags) -> String {
            var text = ""
            if modifiers.contains(.control) { text += "⌃" }
            if modifiers.contains(.option) { text += "⌥" }
            if modifiers.contains(.shift) { text += "⇧" }
            if modifiers.contains(.command) { text += "⌘" }
            let keys: [String: String] = ["\t": "⇥", "\r": "↩", "\u{1b}": "esc", " ": "Space"]
            return text + (keys[character] ?? character.uppercased())
        }
    }

    enum Action {
        /// Our own code, run against the app (its `front` window and so on).
        case run(@MainActor (AppModel) -> Void)
        /// A standard AppKit action, sent along the responder chain: whatever
        /// has focus (a text view, the key window, the app) answers and
        /// validates it.
        case send(Selector)
    }

    /// Stable and unique: "file.newTab", "view.reader".
    let id: String
    let title: String
    let key: Key?
    /// Hidden from the menu but its shortcut still works (⌘1…⌘9).
    let isHidden: Bool
    let action: Action
    /// Greys the item out when false. Checked each time the menu is shown or
    /// a shortcut is pressed.
    let isEnabled: (@MainActor (AppModel) -> Bool)?
    /// For toggles: drives the checkmark.
    let isOn: (@MainActor (AppModel) -> Bool)?

    init(
        _ id: String,
        _ title: String,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        hidden: Bool = false,
        isOn: (@MainActor (AppModel) -> Bool)? = nil,
        isEnabled: (@MainActor (AppModel) -> Bool)? = nil,
        run: @escaping @MainActor (AppModel) -> Void
    ) {
        self.init(id, title, key: key, modifiers: modifiers, hidden: hidden, action: .run(run), isEnabled: isEnabled, isOn: isOn)
    }

    init(_ id: String, _ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = .command, send selector: Selector) {
        self.init(id, title, key: key, modifiers: modifiers, hidden: false, action: .send(selector), isEnabled: nil, isOn: nil)
    }

    private init(
        _ id: String, _ title: String, key: String, modifiers: NSEvent.ModifierFlags, hidden: Bool,
        action: Action, isEnabled: (@MainActor (AppModel) -> Bool)?, isOn: (@MainActor (AppModel) -> Bool)?
    ) {
        self.id = id
        self.title = title
        self.key = key.isEmpty ? nil : Key(character: key, modifiers: modifiers)
        self.isHidden = hidden
        self.action = action
        self.isEnabled = isEnabled
        self.isOn = isOn
    }

    /// Whether it can run now. AppKit's own actions answer that through the
    /// responder chain instead, so they say yes here.
    @MainActor func canRun(in app: AppModel) -> Bool {
        isEnabled?(app) ?? true
    }

    /// Runs our own code if it's available now; AppKit's actions go to
    /// whatever has focus.
    @MainActor func perform(in app: AppModel) {
        switch action {
        case .run(let run):
            guard canRun(in: app) else { return }
            run(app)
        case .send(let selector):
            NSApp.sendAction(selector, to: nil, from: nil)
        }
    }
}

/// One menu of the menu bar, or a submenu, as data.
struct MenuSpec {
    enum Role {
        case standard
        /// `NSApp.windowsMenu`: AppKit lists the windows at its end.
        case windows
        /// `NSApp.helpMenu`: gets the system's help search field.
        case help
    }

    enum Content {
        case items([MenuEntry])
        /// Rebuilt from the app each time the menu opens or its shortcuts are
        /// checked (Spaces).
        case dynamic(@MainActor (AppModel) -> [MenuEntry])
    }

    let title: String
    var role: Role = .standard
    let content: Content

    init(_ title: String, role: Role = .standard, _ items: [MenuEntry]) {
        self.title = title
        self.role = role
        content = .items(items)
    }

    init(_ title: String, dynamic entries: @escaping @MainActor (AppModel) -> [MenuEntry]) {
        self.title = title
        content = .dynamic(entries)
    }

    /// Every command declared here, submenus included; not dynamic ones.
    var staticCommands: [Command] {
        guard case .items(let entries) = content else { return [] }
        return entries.flatMap { entry -> [Command] in
            switch entry {
            case .command(let command): [command]
            case .submenu(let submenu): submenu.staticCommands
            case .separator: []
            }
        }
    }
}

enum MenuEntry {
    case command(Command)
    case separator
    case submenu(MenuSpec)
}
