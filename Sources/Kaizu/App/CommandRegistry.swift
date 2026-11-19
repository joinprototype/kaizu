import AppKit

/// Every main-menu command, in menu order. `MainMenu` builds the menu bar
/// from this; the command bar finds these by name and the Keyboard
/// Shortcuts card lists their keys.
enum CommandRegistry {
    static let mainMenu: [MenuSpec] = {
        var menus = [kaizuMenu, fileMenu, editMenu, viewMenu, historyMenu, tabsMenu, spacesMenu, windowMenu]
        #if DEBUG
        menus.append(debugMenu)
        #endif
        menus.append(helpMenu)
        return menus
    }()

    /// Every command the menus declare up front, by id (not the Spaces
    /// menu's, which follow the space list).
    static let commands: [String: Command] = Dictionary(
        uniqueKeysWithValues: mainMenu.flatMap(\.staticCommands).map { ($0.id, $0) }
    )

    /// "⇧⌘N" for a command's key equivalent, for hints elsewhere.
    static func shortcut(_ id: String) -> String? {
        assert(commands[id] != nil, "No command \(id)")
        return commands[id]?.key?.label
    }

    private static let kaizuMenu = MenuSpec("Kaizu", [
        .command(Command("app.about", "About Kaizu") { UtilityWindows.showAbout(app: $0) }),
        .command(Command("app.checkForUpdates", "Check for Updates…") { Updates.checkNow(app: $0) }),
        .separator,
        .command(Command("app.settings", "Settings…", key: ",") { UtilityWindows.showSettings(app: $0) }),
        .separator,
        .command(Command("app.hide", "Hide Kaizu", key: "h", send: #selector(NSApplication.hide(_:)))),
        .command(Command("app.hideOthers", "Hide Others", key: "h", modifiers: [.command, .option],
                         send: #selector(NSApplication.hideOtherApplications(_:)))),
        .command(Command("app.showAll", "Show All", send: #selector(NSApplication.unhideAllApplications(_:)))),
        .separator,
        .command(Command("app.quit", "Quit Kaizu", key: "q", send: #selector(NSApplication.terminate(_:)))),
    ])

    private static let fileMenu = MenuSpec("File", [
        .command(Command("file.newTab", "New Tab", key: "t") { $0.front.showCommandBar(.newTab) }),
        .command(Command("file.newWindow", "New Window", key: "n") { $0.front.openNewWindow() }),
        .command(Command("file.openLocation", "Open Location…", key: "l") { $0.front.showCommandBar(.currentTab) }),
        .command(Command("file.reopenClosedTab", "Reopen Closed Tab", key: "t", modifiers: [.command, .shift]) {
            $0.front.reopenClosedTab()
        }),
        .command(Command("file.newLittleWindow", "New Little Window", key: "n", modifiers: [.command, .option]) {
            $0.front.openLittleWindow()
        }),
        .command(Command("file.newPrivateWindow", "New Private Window", key: "p", modifiers: [.command, .shift]) {
            $0.front.openPrivateWindow()
        }),
        .command(Command("file.promoteLittleWindow", "Open Little Window in Kaizu", key: "o",
                         isEnabled: { $0.keyLittleWindow != nil }) { $0.keyLittleWindow?.promote() }),
        .separator,
        .command(Command("file.newSpace", "New Space…", key: "n", modifiers: [.command, .shift]) { $0.front.beginNewSpace() }),
        .command(Command("file.importFromArc", "Import from Arc…") { UtilityWindows.showArcImport(app: $0) }),
        .command(Command("file.importBrowsingData", "Import Browsing Data…") { UtilityWindows.showBrowsingDataImport(app: $0) }),
        .separator,
        .command(Command("file.capture", "Capture…", key: "2", modifiers: [.command, .shift]) { app in
            app.front.commandTab.map { app.front.beginCapture(of: $0) }
        }),
        .command(Command("file.exportPDF", "Export as PDF…") { $0.front.commandTab?.exportPDF() }),
        .command(Command("file.print", "Print…", key: "p") { $0.front.commandTab?.printPage() }),
        .separator,
        .command(Command("file.closeTab", "Close Tab", key: "w") { $0.front.closeSelectedTab() }),
        .command(Command("file.closeWindow", "Close Window", key: "w", modifiers: [.command, .shift],
                         send: #selector(NSWindow.performClose(_:)))),
    ])

    /// The standard items: whichever text view or web view has focus answers them.
    private static let spellingMenu = MenuSpec("Spelling and Grammar", [
        .command(Command("edit.spelling.showPanel", "Show Spelling and Grammar", key: ":", send: #selector(NSText.showGuessPanel(_:)))),
        .command(Command("edit.spelling.checkNow", "Check Document Now", key: ";", send: #selector(NSText.checkSpelling(_:)))),
        .separator,
        .command(Command("edit.spelling.whileTyping", "Check Spelling While Typing",
                         send: #selector(NSTextView.toggleContinuousSpellChecking(_:)))),
        .command(Command("edit.spelling.grammar", "Check Grammar With Spelling", send: #selector(NSTextView.toggleGrammarChecking(_:)))),
        .command(Command("edit.spelling.autocorrect", "Correct Spelling Automatically",
                         send: #selector(NSTextView.toggleAutomaticSpellingCorrection(_:)))),
    ])

    /// The find bar is the main window's: not for a little window's page.
    private static func inMainWindow(_ app: AppModel) -> Bool {
        app.front.window?.isKeyWindow == true
    }

    private static let editMenu = MenuSpec("Edit", [
        .command(Command("edit.undo", "Undo", key: "z", send: Selector(("undo:")))),
        .command(Command("edit.redo", "Redo", key: "z", modifiers: [.command, .shift], send: Selector(("redo:")))),
        .separator,
        .command(Command("edit.cut", "Cut", key: "x", send: #selector(NSText.cut(_:)))),
        .command(Command("edit.copy", "Copy", key: "c", send: #selector(NSText.copy(_:)))),
        .command(Command("edit.paste", "Paste", key: "v", send: #selector(NSText.paste(_:)))),
        .command(Command("edit.pasteAndMatchStyle", "Paste and Match Style", key: "v", modifiers: [.command, .option, .shift],
                         send: #selector(NSTextView.pasteAsPlainText(_:)))),
        .command(Command("edit.delete", "Delete", send: #selector(NSText.delete(_:)))),
        .command(Command("edit.selectAll", "Select All", key: "a", send: #selector(NSText.selectAll(_:)))),
        .separator,
        .submenu(spellingMenu),
        .separator,
        .command(Command("edit.find", "Find…", key: "f") { if inMainWindow($0) { $0.front.showFindBar() } }),
        .command(Command("edit.findNext", "Find Next", key: "g") { if inMainWindow($0) { $0.front.findNext() } }),
        .command(Command("edit.findPrevious", "Find Previous", key: "g", modifiers: [.command, .shift]) {
            if inMainWindow($0) { $0.front.findNext(backwards: true) }
        }),
    ])

    private static let viewMenu = MenuSpec("View", [
        .command(Command("view.toggleSidebar", "Toggle Sidebar", key: "s") { $0.front.toggleSidebar() }),
        // Reader shows in the main window, for its tab only.
        .command(Command("view.reader", "Show Reader", key: "r", modifiers: [.command, .shift], isOn: { $0.front.reader != nil }) {
            if inMainWindow($0) { $0.front.toggleReader() }
        }),
        .command(Command("view.splitWithRecentTab", "Split with Recent Tab", key: "=", modifiers: [.control, .shift],
                         isEnabled: { $0.front.recentSplitPartner != nil }) { $0.front.splitWithRecentTab() }),
        .command(Command("view.closeSplit", "Close Split View") { $0.front.closeSplit() }),
        .separator,
        .command(Command("view.blockAds", "Block Ads & Trackers", isOn: { $0.front.contentBlocker.isEnabled }) {
            $0.front.toggleContentBlocking()
        }),
        .command(Command("view.pauseBlockingOnSite", "Pause Blocking on This Site", isOn: { app in
            let tab = app.front.commandTab
            return app.front.contentBlocker.isPaused(on: tab?.url, privateID: tab?.profile.privateID)
        }) {
            $0.front.toggleBlockingOnCurrentSite($0.front.commandTab)
        }),
        .command(Command("view.rejectCookiePopups", "Auto-Reject Cookie Pop-ups", isOn: { $0.front.contentBlocker.isCookieRejectionEnabled }) {
            $0.front.toggleCookieRejection()
        }),
        .command(Command("view.hideDistractingItems", "Hide Distracting Items…") { app in
            if let tab = app.front.commandTab { app.front.beginHidingItems(on: tab) }
        }),
        .command(Command("view.watchPart", "Watch Part of Page…") { app in
            if let tab = app.front.commandTab { app.front.beginHidingItems(on: tab, for: .watch) }
        }),
        .separator,
        .command(Command("view.reload", "Reload Page", key: "r") { $0.front.commandTab?.reload() }),
        .command(Command("view.reloadIgnoringCache", "Reload Ignoring Cache", key: "r", modifiers: [.command, .option]) {
            $0.front.commandTab?.reload(fromOrigin: true)
        }),
        .command(Command("view.stop", "Stop", key: ".") { $0.front.commandTab?.stopLoading() }),
        .separator,
        .command(Command("view.zoomIn", "Zoom In", key: "=") { $0.front.commandTab?.zoom(by: 0.1) }),
        .command(Command("view.zoomOut", "Zoom Out", key: "-") { $0.front.commandTab?.zoom(by: -0.1) }),
        .command(Command("view.actualSize", "Actual Size", key: "0") { $0.front.commandTab?.resetZoom() }),
        .separator,
        .command(Command("view.fullScreen", "Enter Full Screen", key: "f", modifiers: [.command, .control],
                         send: #selector(NSWindow.toggleFullScreen(_:)))),
    ])

    private static let historyMenu = MenuSpec("History", [
        .command(Command("history.back", "Back", key: "[") { $0.front.commandTab?.goBack() }),
        .command(Command("history.forward", "Forward", key: "]") { $0.front.commandTab?.goForward() }),
        .separator,
        .command(Command("history.showAll", "Show All History", key: "y") { UtilityWindows.showHistory(app: $0) }),
        .command(Command("history.archivedTabs", "Recently Archived Tabs…", isEnabled: { !$0.front.isPrivate }) { app in
            let store = app.front
            guard !store.isPrivate else { return }
            store.window?.makeKeyAndOrderFront(nil)
            store.showingArchive = true
        }),
        .command(Command("history.clear", "Clear History…") { $0.front.clearHistory() }),
    ])

    private static let tabsMenu = MenuSpec("Tabs", [
        // ⌃Tab in the main window is the switcher's key monitor; this is
        // the menu path. Clicked, there's no ⌃ to release: switch at once.
        .command(Command("tabs.recent", "Recent Tabs", key: "\t", modifiers: .control) { app in
            guard inMainWindow(app) else { return }
            app.front.advanceTabSwitcher(backwards: false)
            if !NSEvent.modifierFlags.contains(.control) { app.front.commitTabSwitcher() }
        }),
        .command(Command("tabs.next", "Next Tab", key: arrow(NSDownArrowFunctionKey), modifiers: [.command, .option]) {
            $0.front.selectAdjacentTab(1)
        }),
        .command(Command("tabs.previous", "Previous Tab", key: arrow(NSUpArrowFunctionKey), modifiers: [.command, .option]) {
            $0.front.selectAdjacentTab(-1)
        }),
        .separator,
        .command(Command("tabs.togglePin", "Pin / Unpin Tab", key: "d") { app in
            if let tab = app.front.commandTab { app.front.togglePin(tab) }
        }),
        .command(Command("tabs.copyLink", "Copy Link", key: "c", modifiers: [.command, .shift]) { app in
            app.front.commandTab.map { app.front.copyLink(of: $0) }
        }),
        .command(Command("tabs.copyMarkdownLink", "Copy as Markdown Link", key: "c", modifiers: [.command, .shift, .option]) { app in
            app.front.commandTab.map { app.front.copyLink(of: $0, asMarkdown: true) }
        }),
    ] + (1...9).map { number -> MenuEntry in
        .command(Command("tabs.select.\(number)", number == 9 ? "Select Last Tab" : "Select Tab \(number)", key: "\(number)", hidden: true) {
            $0.front.selectTab(number: number)
        })
    })

    /// Follows the space list, so it's built when it opens.
    private static let spacesMenu = MenuSpec("Spaces") { app in spaceEntries(app.spaces) }

    /// ⌃1…⌃9 switch to the first nine spaces. Unavailable once its space is
    /// gone (the command bar can hold one a moment longer than the menu).
    static func spaceEntries(_ spaces: [Space]) -> [MenuEntry] {
        spaces.enumerated().map { index, space -> MenuEntry in
            .command(Command("spaces.switch.\(space.id)", space.name, key: index < 9 ? "\(index + 1)" : "", modifiers: .control,
                             isOn: { $0.regularFront.activeSpaceID == space.id },
                             isEnabled: { app in app.spaces.contains { $0 === space } }) { app in
                app.regularFront.window?.makeKeyAndOrderFront(nil)
                app.regularFront.switchTo(space)
            })
        } + [
            .separator,
            .command(Command("spaces.new", "New Space…") { $0.front.beginNewSpace() }),
            .command(Command("spaces.editCurrent", "Edit Current Space…") { $0.regularFront.beginEditing($0.regularFront.activeSpace) }),
        ]
    }

    private static let windowMenu = MenuSpec("Window", role: .windows, [
        .command(Command("window.minimize", "Minimize", key: "m", send: #selector(NSWindow.performMiniaturize(_:)))),
        .command(Command("window.zoom", "Zoom", send: #selector(NSWindow.performZoom(_:)))),
        .separator,
        .command(Command("window.bringAllToFront", "Bring All to Front", send: #selector(NSApplication.arrangeInFront(_:)))),
    ])

    #if DEBUG
    private static let debugMenu = MenuSpec("Debug", [
        .command(Command("debug.cookiePopupResult", "Cookie Pop-up Result") { $0.front.showCookiePopupResult() }),
    ])
    #endif

    private static let helpMenu = MenuSpec("Help", role: .help, [
        .command(Command("help.keyboardShortcuts", "Keyboard Shortcuts", key: "/") { UtilityWindows.showKeyboardShortcuts(app: $0) }),
        .separator,
        .command(Command("help.reportBug", "Report a Bug…") { UtilityWindows.showBugReport(app: $0) }),
        .command(Command("help.reportBrokenSite", "Report a Broken Site…") { $0.front.reportBrokenSite() }),
    ])

    private static func arrow(_ key: Int) -> String {
        String(Character(UnicodeScalar(UInt16(key))!))
    }
}
