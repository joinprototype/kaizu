import AppKit

/// Menu item that runs a closure instead of dispatching a selector.
@MainActor
final class ActionMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void
    /// For toggles: drives the checkmark each time the menu is shown.
    private let isOn: (@MainActor () -> Bool)?

    init(
        _ title: String,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        hidden: Bool = false,
        isOn: (@MainActor () -> Bool)? = nil,
        handler: @escaping @MainActor () -> Void
    ) {
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
        return true
    }
}

@MainActor
enum MainMenu {
    static func make(store: BrowserStore) -> NSMenu {
        let menu = NSMenu()
        menu.addSubmenu(appMenu(store))
        menu.addSubmenu(fileMenu(store))
        menu.addSubmenu(editMenu(store))
        menu.addSubmenu(viewMenu(store))
        menu.addSubmenu(historyMenu(store))
        menu.addSubmenu(tabsMenu(store))
        menu.addSubmenu(SpacesMenu(store: store))
        let window = windowMenu()
        menu.addSubmenu(window)
        NSApp.windowsMenu = window
        #if DEBUG
        menu.addSubmenu(debugMenu(store))
        #endif
        let help = helpMenu(store)
        menu.addSubmenu(help)
        NSApp.helpMenu = help
        return menu
    }

    private static func appMenu(_ store: BrowserStore) -> NSMenu {
        let menu = NSMenu(title: "Kaizu")
        menu.addItem(withTitle: "About Kaizu", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(ActionMenuItem("Check for Updates…") { Updates.checkNow(store: store) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Settings…", key: ",") { UtilityWindows.showSettings(store: store) })
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Kaizu", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Kaizu", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func fileMenu(_ store: BrowserStore) -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(ActionMenuItem("New Tab", key: "t") { store.showCommandBar(.newTab) })
        menu.addItem(ActionMenuItem("Open Location…", key: "l") { store.showCommandBar(.currentTab) })
        menu.addItem(ActionMenuItem("Reopen Closed Tab", key: "t", modifiers: [.command, .shift]) { store.reopenClosedTab() })
        menu.addItem(ActionMenuItem("New Little Window", key: "n", modifiers: [.command, .option]) { store.openLittleWindow() })
        menu.addItem(ActionMenuItem("New Private Window", key: "p", modifiers: [.command, .shift]) { store.openPrivateWindow() })
        menu.addItem(ActionMenuItem("Open Little Window in Kaizu", key: "o") { store.keyLittleWindow?.promote() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("New Space…", key: "n", modifiers: [.command, .shift]) { store.beginNewSpace() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Capture…", key: "2", modifiers: [.command, .shift]) {
            store.commandTab.map { store.beginCapture(of: $0) }
        })
        menu.addItem(ActionMenuItem("Export as PDF…") { store.commandTab?.exportPDF() })
        menu.addItem(ActionMenuItem("Print…", key: "p") { store.commandTab?.printPage() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Close Tab", key: "w") { store.closeSelectedTab() })
        let closeWindow = menu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeWindow.keyEquivalentModifierMask = [.command, .shift]
        return menu
    }

    private static func editMenu(_ store: BrowserStore) -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let pastePlain = menu.addItem(withTitle: "Paste and Match Style", action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "v")
        pastePlain.keyEquivalentModifierMask = [.command, .option, .shift]
        menu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())
        // The find bar is the main window's: not for a little window's page.
        let inMainWindow = { store.window?.isKeyWindow == true }
        menu.addItem(ActionMenuItem("Find…", key: "f") { if inMainWindow() { store.showFindBar() } })
        menu.addItem(ActionMenuItem("Find Next", key: "g") { if inMainWindow() { store.findNext() } })
        menu.addItem(ActionMenuItem("Find Previous", key: "g", modifiers: [.command, .shift]) { if inMainWindow() { store.findNext(backwards: true) } })
        return menu
    }

    private static func viewMenu(_ store: BrowserStore) -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(ActionMenuItem("Toggle Sidebar", key: "s") { store.toggleSidebar() })
        // Reader shows in the main window, for its tab only.
        menu.addItem(ActionMenuItem("Show Reader", key: "r", modifiers: [.command, .shift], isOn: { store.reader != nil }) {
            if store.window?.isKeyWindow == true { store.toggleReader() }
        })
        menu.addItem(ActionMenuItem("Split with Recent Tab", key: "=", modifiers: [.control, .shift]) { store.splitWithRecentTab() })
        menu.addItem(ActionMenuItem("Close Split View") { store.closeSplit() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Block Ads & Trackers", isOn: { store.contentBlocker.isEnabled }) {
            store.toggleContentBlocking()
        })
        menu.addItem(ActionMenuItem("Pause Blocking on This Site", isOn: { store.contentBlocker.isPaused(on: store.commandTab?.url) }) {
            store.toggleBlockingOnCurrentSite(store.commandTab)
        })
        menu.addItem(ActionMenuItem("Auto-Reject Cookie Pop-ups", isOn: { store.contentBlocker.isCookieRejectionEnabled }) {
            store.toggleCookieRejection()
        })
        menu.addItem(ActionMenuItem("Hide Distracting Items…") {
            if let tab = store.commandTab { store.beginHidingItems(on: tab) }
        })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Reload Page", key: "r") { store.commandTab?.reload() })
        menu.addItem(ActionMenuItem("Reload Ignoring Cache", key: "r", modifiers: [.command, .option]) { store.commandTab?.reload(fromOrigin: true) })
        menu.addItem(ActionMenuItem("Stop", key: ".") { store.commandTab?.stopLoading() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Zoom In", key: "=") { store.commandTab?.zoom(by: 0.1) })
        menu.addItem(ActionMenuItem("Zoom Out", key: "-") { store.commandTab?.zoom(by: -0.1) })
        menu.addItem(ActionMenuItem("Actual Size", key: "0") { store.commandTab?.resetZoom() })
        menu.addItem(.separator())
        let fullScreen = menu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        return menu
    }

    private static func historyMenu(_ store: BrowserStore) -> NSMenu {
        let menu = NSMenu(title: "History")
        menu.addItem(ActionMenuItem("Back", key: "[") { store.commandTab?.goBack() })
        menu.addItem(ActionMenuItem("Forward", key: "]") { store.commandTab?.goForward() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Show All History", key: "y") { UtilityWindows.showHistory(store: store) })
        menu.addItem(ActionMenuItem("Clear History…") { store.clearHistory() })
        return menu
    }

    private static func tabsMenu(_ store: BrowserStore) -> NSMenu {
        let menu = NSMenu(title: "Tabs")
        // ⌃Tab in the main window is the switcher's key monitor; this is
        // the menu path. Clicked, there's no ⌃ to release: switch at once.
        menu.addItem(ActionMenuItem("Recent Tabs", key: "\t", modifiers: .control) {
            guard store.window?.isKeyWindow == true else { return }
            store.advanceTabSwitcher(backwards: false)
            if !NSEvent.modifierFlags.contains(.control) { store.commitTabSwitcher() }
        })
        menu.addItem(ActionMenuItem("Next Tab", key: arrow(NSDownArrowFunctionKey), modifiers: [.command, .option]) { store.selectAdjacentTab(1) })
        menu.addItem(ActionMenuItem("Previous Tab", key: arrow(NSUpArrowFunctionKey), modifiers: [.command, .option]) { store.selectAdjacentTab(-1) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Pin / Unpin Tab", key: "d") {
            if let tab = store.commandTab { store.togglePin(tab) }
        })
        menu.addItem(ActionMenuItem("Copy Link", key: "c", modifiers: [.command, .shift]) { store.commandTab.map { store.copyLink(of: $0) } })
        menu.addItem(ActionMenuItem("Copy as Markdown Link", key: "c", modifiers: [.command, .shift, .option]) { store.commandTab.map { store.copyLink(of: $0, asMarkdown: true) } })
        for number in 1...9 {
            let title = number == 9 ? "Select Last Tab" : "Select Tab \(number)"
            menu.addItem(ActionMenuItem(title, key: "\(number)", hidden: true) { store.selectTab(number: number) })
        }
        return menu
    }

    #if DEBUG
    private static func debugMenu(_ store: BrowserStore) -> NSMenu {
        let menu = NSMenu(title: "Debug")
        menu.addItem(ActionMenuItem("Cookie Pop-up Result") { store.showCookiePopupResult() })
        return menu
    }
    #endif

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        return menu
    }

    private static func helpMenu(_ store: BrowserStore) -> NSMenu {
        let menu = NSMenu(title: "Help")
        menu.addItem(ActionMenuItem("Report a Bug…") { UtilityWindows.showBugReport(store: store) })
        return menu
    }

    private static func arrow(_ key: Int) -> String {
        String(Character(UnicodeScalar(UInt16(key))!))
    }
}

/// Rebuilt every time it opens (or a key equivalent is checked) so it tracks the space list.
@MainActor
final class SpacesMenu: NSMenu, NSMenuDelegate {
    private let store: BrowserStore

    init(store: BrowserStore) {
        self.store = store
        super.init(title: "Spaces")
        delegate = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        removeAllItems()
        for (index, space) in store.spaces.enumerated() {
            let key = index < 9 ? "\(index + 1)" : ""
            let item = ActionMenuItem(space.name, key: key, modifiers: .control) { [store] in
                store.switchTo(space)
            }
            item.state = space.id == store.activeSpaceID ? .on : .off
            addItem(item)
        }
        addItem(.separator())
        addItem(ActionMenuItem("New Space…") { [store] in store.beginNewSpace() })
        addItem(ActionMenuItem("Edit Current Space…") { [store] in store.beginEditing(store.activeSpace) })
    }
}

private extension NSMenu {
    func addSubmenu(_ submenu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
