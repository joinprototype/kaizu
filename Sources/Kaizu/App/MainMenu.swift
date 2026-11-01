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
    static func make(app: AppModel) -> NSMenu {
        let menu = NSMenu()
        menu.addSubmenu(appMenu(app))
        menu.addSubmenu(fileMenu(app))
        menu.addSubmenu(editMenu(app))
        menu.addSubmenu(viewMenu(app))
        menu.addSubmenu(historyMenu(app))
        menu.addSubmenu(tabsMenu(app))
        menu.addSubmenu(SpacesMenu(app: app))
        let window = windowMenu()
        menu.addSubmenu(window)
        NSApp.windowsMenu = window
        #if DEBUG
        menu.addSubmenu(debugMenu(app))
        #endif
        let help = helpMenu(app)
        menu.addSubmenu(help)
        NSApp.helpMenu = help
        return menu
    }

    private static func appMenu(_ app: AppModel) -> NSMenu {
        let menu = NSMenu(title: "Kaizu")
        menu.addItem(ActionMenuItem("About Kaizu") { UtilityWindows.showAbout(app: app) })
        menu.addItem(ActionMenuItem("Check for Updates…") { Updates.checkNow(app: app) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Settings…", key: ",") { UtilityWindows.showSettings(app: app) })
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Kaizu", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Kaizu", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func fileMenu(_ app: AppModel) -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(ActionMenuItem("New Tab", key: "t") { app.front.showCommandBar(.newTab) })
        menu.addItem(ActionMenuItem("New Window", key: "n") { app.front.openNewWindow() })
        menu.addItem(ActionMenuItem("Open Location…", key: "l") { app.front.showCommandBar(.currentTab) })
        menu.addItem(ActionMenuItem("Reopen Closed Tab", key: "t", modifiers: [.command, .shift]) { app.front.reopenClosedTab() })
        menu.addItem(ActionMenuItem("New Little Window", key: "n", modifiers: [.command, .option]) { app.front.openLittleWindow() })
        menu.addItem(ActionMenuItem("New Private Window", key: "p", modifiers: [.command, .shift]) { app.front.openPrivateWindow() })
        menu.addItem(ActionMenuItem("Open Little Window in Kaizu", key: "o") { app.keyLittleWindow?.promote() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("New Space…", key: "n", modifiers: [.command, .shift]) { app.front.beginNewSpace() })
        menu.addItem(ActionMenuItem("Import from Arc…") { UtilityWindows.showArcImport(app: app) })
        menu.addItem(ActionMenuItem("Import Browsing Data…") { UtilityWindows.showBrowsingDataImport(app: app) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Capture…", key: "2", modifiers: [.command, .shift]) {
            app.front.commandTab.map { app.front.beginCapture(of: $0) }
        })
        menu.addItem(ActionMenuItem("Export as PDF…") { app.front.commandTab?.exportPDF() })
        menu.addItem(ActionMenuItem("Print…", key: "p") { app.front.commandTab?.printPage() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Close Tab", key: "w") { app.front.closeSelectedTab() })
        let closeWindow = menu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeWindow.keyEquivalentModifierMask = [.command, .shift]
        return menu
    }

    private static func editMenu(_ app: AppModel) -> NSMenu {
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
        let inMainWindow = { app.front.window?.isKeyWindow == true }
        menu.addItem(ActionMenuItem("Find…", key: "f") { if inMainWindow() { app.front.showFindBar() } })
        menu.addItem(ActionMenuItem("Find Next", key: "g") { if inMainWindow() { app.front.findNext() } })
        menu.addItem(ActionMenuItem("Find Previous", key: "g", modifiers: [.command, .shift]) { if inMainWindow() { app.front.findNext(backwards: true) } })
        return menu
    }

    private static func viewMenu(_ app: AppModel) -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(ActionMenuItem("Toggle Sidebar", key: "s") { app.front.toggleSidebar() })
        // Reader shows in the main window, for its tab only.
        menu.addItem(ActionMenuItem("Show Reader", key: "r", modifiers: [.command, .shift], isOn: { app.front.reader != nil }) {
            if app.front.window?.isKeyWindow == true { app.front.toggleReader() }
        })
        menu.addItem(ActionMenuItem("Split with Recent Tab", key: "=", modifiers: [.control, .shift]) { app.front.splitWithRecentTab() })
        menu.addItem(ActionMenuItem("Close Split View") { app.front.closeSplit() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Block Ads & Trackers", isOn: { app.front.contentBlocker.isEnabled }) {
            app.front.toggleContentBlocking()
        })
        menu.addItem(ActionMenuItem("Pause Blocking on This Site", isOn: { app.front.contentBlocker.isPaused(on: app.front.commandTab?.url) }) {
            app.front.toggleBlockingOnCurrentSite(app.front.commandTab)
        })
        menu.addItem(ActionMenuItem("Auto-Reject Cookie Pop-ups", isOn: { app.front.contentBlocker.isCookieRejectionEnabled }) {
            app.front.toggleCookieRejection()
        })
        menu.addItem(ActionMenuItem("Hide Distracting Items…") {
            if let tab = app.front.commandTab { app.front.beginHidingItems(on: tab) }
        })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Reload Page", key: "r") { app.front.commandTab?.reload() })
        menu.addItem(ActionMenuItem("Reload Ignoring Cache", key: "r", modifiers: [.command, .option]) { app.front.commandTab?.reload(fromOrigin: true) })
        menu.addItem(ActionMenuItem("Stop", key: ".") { app.front.commandTab?.stopLoading() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Zoom In", key: "=") { app.front.commandTab?.zoom(by: 0.1) })
        menu.addItem(ActionMenuItem("Zoom Out", key: "-") { app.front.commandTab?.zoom(by: -0.1) })
        menu.addItem(ActionMenuItem("Actual Size", key: "0") { app.front.commandTab?.resetZoom() })
        menu.addItem(.separator())
        let fullScreen = menu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        return menu
    }

    private static func historyMenu(_ app: AppModel) -> NSMenu {
        let menu = NSMenu(title: "History")
        menu.addItem(ActionMenuItem("Back", key: "[") { app.front.commandTab?.goBack() })
        menu.addItem(ActionMenuItem("Forward", key: "]") { app.front.commandTab?.goForward() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Show All History", key: "y") { UtilityWindows.showHistory(app: app) })
        menu.addItem(ActionMenuItem("Clear History…") { app.front.clearHistory() })
        return menu
    }

    private static func tabsMenu(_ app: AppModel) -> NSMenu {
        let menu = NSMenu(title: "Tabs")
        // ⌃Tab in the main window is the switcher's key monitor; this is
        // the menu path. Clicked, there's no ⌃ to release: switch at once.
        menu.addItem(ActionMenuItem("Recent Tabs", key: "\t", modifiers: .control) {
            guard app.front.window?.isKeyWindow == true else { return }
            app.front.advanceTabSwitcher(backwards: false)
            if !NSEvent.modifierFlags.contains(.control) { app.front.commitTabSwitcher() }
        })
        menu.addItem(ActionMenuItem("Next Tab", key: arrow(NSDownArrowFunctionKey), modifiers: [.command, .option]) { app.front.selectAdjacentTab(1) })
        menu.addItem(ActionMenuItem("Previous Tab", key: arrow(NSUpArrowFunctionKey), modifiers: [.command, .option]) { app.front.selectAdjacentTab(-1) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Pin / Unpin Tab", key: "d") {
            if let tab = app.front.commandTab { app.front.togglePin(tab) }
        })
        menu.addItem(ActionMenuItem("Copy Link", key: "c", modifiers: [.command, .shift]) { app.front.commandTab.map { app.front.copyLink(of: $0) } })
        menu.addItem(ActionMenuItem("Copy as Markdown Link", key: "c", modifiers: [.command, .shift, .option]) { app.front.commandTab.map { app.front.copyLink(of: $0, asMarkdown: true) } })
        for number in 1...9 {
            let title = number == 9 ? "Select Last Tab" : "Select Tab \(number)"
            menu.addItem(ActionMenuItem(title, key: "\(number)", hidden: true) { app.front.selectTab(number: number) })
        }
        return menu
    }

    #if DEBUG
    private static func debugMenu(_ app: AppModel) -> NSMenu {
        let menu = NSMenu(title: "Debug")
        menu.addItem(ActionMenuItem("Cookie Pop-up Result") { app.front.showCookiePopupResult() })
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

    private static func helpMenu(_ app: AppModel) -> NSMenu {
        let menu = NSMenu(title: "Help")
        menu.addItem(ActionMenuItem("Keyboard Shortcuts", key: "/") { UtilityWindows.showKeyboardShortcuts(app: app) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Report a Bug…") { UtilityWindows.showBugReport(app: app) })
        menu.addItem(ActionMenuItem("Report a Broken Site…") { app.front.reportBrokenSite() })
        return menu
    }

    private static func arrow(_ key: Int) -> String {
        String(Character(UnicodeScalar(UInt16(key))!))
    }
}

/// Rebuilt every time it opens (or a key equivalent is checked) so it tracks the space list.
@MainActor
final class SpacesMenu: NSMenu, NSMenuDelegate {
    private let app: AppModel

    init(app: AppModel) {
        self.app = app
        super.init(title: "Spaces")
        delegate = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        removeAllItems()
        for (index, space) in app.spaces.enumerated() {
            let key = index < 9 ? "\(index + 1)" : ""
            let item = ActionMenuItem(space.name, key: key, modifiers: .control) { [app] in
                app.regularFront.window?.makeKeyAndOrderFront(nil)
                app.regularFront.switchTo(space)
            }
            item.state = space.id == app.regularFront.activeSpaceID ? .on : .off
            addItem(item)
        }
        addItem(.separator())
        addItem(ActionMenuItem("New Space…") { [app] in app.front.beginNewSpace() })
        addItem(ActionMenuItem("Edit Current Space…") { [app] in app.regularFront.beginEditing(app.regularFront.activeSpace) })
    }
}

private extension NSMenu {
    func addSubmenu(_ submenu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
