import AppKit

/// Menu item that runs a closure instead of dispatching a selector.
@MainActor
final class ActionMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void
    /// For toggles: drives the checkmark each time the menu is shown.
    private let isOn: (@MainActor () -> Bool)?

    private let available: @MainActor () -> Bool

    init(
        _ title: String,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        hidden: Bool = false,
        isOn: (@MainActor () -> Bool)? = nil,
        available: @escaping @MainActor () -> Bool = { true },
        handler: @escaping @MainActor () -> Void
    ) {
        self.available = available
        self.handler = handler
        self.isOn = isOn
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
        target = self
        if hidden {
            isHidden = true
            allowsKeyEquivalentWhenHidden = true
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func fire() {
        handler()
    }
}

extension ActionMenuItem: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let isOn {
            state = isOn() ? .on : .off
        }
        return available()
    }
}


/// Builds the menu bar from `CommandRegistry`.
@MainActor
enum MainMenu {
    /// `app` is nil only in tests, which look at the menu's shape: items
    /// then do nothing and are disabled.
    static func make(app: AppModel?) -> NSMenu {
        let menu = NSMenu()
        for spec in CommandRegistry.mainMenu {
            let submenu = build(spec, app: app)
            menu.addSubmenu(submenu)
            switch spec.role {
            case .windows: NSApp.windowsMenu = submenu
            case .help: NSApp.helpMenu = submenu
            case .standard: break
            }
        }
        return menu
    }

    private static func build(_ spec: MenuSpec, app: AppModel?) -> NSMenu {
        switch spec.content {
        case .items(let entries):
            let menu = NSMenu(title: spec.title)
            add(entries, to: menu, app: app)
            return menu
        case .dynamic(let entries):
            return DynamicMenu(title: spec.title, app: app, entries: entries)
        }
    }

    fileprivate static func add(_ entries: [MenuEntry], to menu: NSMenu, app: AppModel?) {
        for entry in entries {
            switch entry {
            case .command(let command): menu.addItem(item(for: command, app: app))
            case .separator: menu.addItem(.separator())
            case .submenu(let spec): menu.addSubmenu(build(spec, app: app))
            }
        }
    }

    /// AppKit's actions get a plain item, as AppKit expects: it copies some
    /// (Enter Full Screen's ⌃⌘F alternate), which a subclass can't survive.
    private static func item(for command: Command, app: AppModel?) -> NSMenuItem {
        let item = switch command.action {
        case .run: CommandMenuItem(command, app: app)
        case .send(let selector): NSMenuItem(title: command.title, action: selector, keyEquivalent: "")
        }
        item.keyEquivalent = command.key?.character ?? ""
        item.keyEquivalentModifierMask = command.key?.modifiers ?? .command
        item.identifier = NSUserInterfaceItemIdentifier(command.id)
        if command.isHidden {
            item.isHidden = true
            item.allowsKeyEquivalentWhenHidden = true
        }
        return item
    }
}

/// A main-menu item that runs a `Command`'s own code.
@MainActor
final class CommandMenuItem: NSMenuItem {
    let command: Command
    private weak var app: AppModel?

    init(_ command: Command, app: AppModel?) {
        self.command = command
        self.app = app
        super.init(title: command.title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// AppKit only sends this once `validateMenuItem` said yes.
    @objc private func fire() {
        guard let app, case .run(let run) = command.action else { return }
        run(app)
    }
}

extension CommandMenuItem: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let app else { return false }
        if let isOn = command.isOn {
            state = isOn(app) ? .on : .off
        }
        return command.canRun(in: app)
    }
}

extension NSMenuItem {
    /// The registry command this item runs, when it's our own code. AppKit's
    /// items have none and are read as they stand: the responder actions it
    /// validates and may retitle or give another key (Enter Full Screen), and
    /// those it adds itself (Close All, Start Dictation, Emoji & Symbols,
    /// AutoFill, the window list).
    var ownCommand: Command? {
        (self as? CommandMenuItem)?.command
    }

    /// "⇧⌘T" for its key equivalent, if it has one.
    var shortcutLabel: String? {
        if let command = ownCommand { return command.key?.label }
        guard !keyEquivalent.isEmpty else { return nil }
        return Command.Key.label(character: keyEquivalent, modifiers: keyEquivalentModifierMask)
    }
}

/// A menu rebuilt from its entries every time it opens (or a key equivalent
/// is checked), so it tracks the space list.
@MainActor
final class DynamicMenu: NSMenu, NSMenuDelegate {
    private weak var app: AppModel?
    private let entries: @MainActor (AppModel) -> [MenuEntry]

    init(title: String, app: AppModel?, entries: @escaping @MainActor (AppModel) -> [MenuEntry]) {
        self.app = app
        self.entries = entries
        super.init(title: title)
        delegate = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        removeAllItems()
        guard let app else { return }
        MainMenu.add(entries(app), to: self, app: app)
    }
}

private extension NSMenu {
    func addSubmenu(_ submenu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
