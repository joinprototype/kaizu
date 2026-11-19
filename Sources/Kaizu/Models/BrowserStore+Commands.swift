import AppKit

/// An action you can run from the command bar by typing its name (Raycast-style).
struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let symbol: String
    /// Extra words it should match ("preferences" for Settings).
    var keywords: [String] = []
    /// Shown as a hint, e.g. "⌘S".
    var shortcut: String?
    let perform: @MainActor () -> Void
}

extension BrowserStore {
    /// Commands available right now; titles adapt to state ("Pin" vs "Unpin").
    var paletteCommands: [PaletteCommand] {
        var commands: [PaletteCommand] = [
            PaletteCommand(id: "settings", title: "Open Settings", symbol: "gearshape", keywords: ["preferences"], shortcut: CommandRegistry.shortcut("app.settings")) {
                UtilityWindows.showSettings(app: self.app)
            },
            PaletteCommand(id: "space.new", title: "New Space", symbol: "plus.square.on.square", keywords: ["profile"], shortcut: CommandRegistry.shortcut("file.newSpace")) {
                self.beginNewSpace()
            },
            PaletteCommand(id: "sidebar", title: "Toggle Sidebar", symbol: "sidebar.left", keywords: ["hide", "show"], shortcut: CommandRegistry.shortcut("view.toggleSidebar")) {
                self.toggleSidebar()
            },
            PaletteCommand(id: "window.new", title: "New Window", symbol: "macwindow.on.rectangle", shortcut: CommandRegistry.shortcut("file.newWindow")) {
                self.openNewWindow()
            },
            PaletteCommand(id: "little", title: "New Little Window", symbol: "macwindow", shortcut: CommandRegistry.shortcut("file.newLittleWindow")) {
                self.openLittleWindow()
            },
            PaletteCommand(id: "private", title: "New Private Window", symbol: "eyeglasses", keywords: ["incognito"], shortcut: CommandRegistry.shortcut("file.newPrivateWindow")) {
                self.openPrivateWindow()
            },
            PaletteCommand(id: "history.show", title: "Show History", symbol: "clock", shortcut: CommandRegistry.shortcut("history.showAll")) {
                UtilityWindows.showHistory(app: self.app)
            },
            PaletteCommand(id: "folder.new", title: "New Folder", symbol: "folder.badge.plus", keywords: ["group"]) {
                self.newFolder()
            },
            PaletteCommand(id: "tab.reopen", title: "Reopen Closed Tab", symbol: "arrow.uturn.backward", keywords: ["undo"], shortcut: CommandRegistry.shortcut("file.reopenClosedTab")) {
                self.reopenClosedTab()
            },
            PaletteCommand(id: "history.clear", title: "Clear History", symbol: "clock.arrow.circlepath", keywords: ["delete", "privacy"]) {
                self.clearHistory()
            },
            PaletteCommand(
                id: "blocking",
                title: contentBlocker.isEnabled ? "Turn Off Ad Blocking" : "Turn On Ad Blocking",
                symbol: "shield", keywords: ["adblock", "tracker", "privacy"]
            ) {
                self.toggleContentBlocking()
            },
            PaletteCommand(id: "downloads", title: "Open Downloads Folder", symbol: "arrow.down.circle") {
                NSWorkspace.shared.open(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
            },
        ]
        if let tab = selectedTab {
            let isPinned = !activeSpace.today.contains(tab)
            commands += [
                PaletteCommand(id: "tab.copy", title: "Copy Link", symbol: "link", keywords: ["url", "share"], shortcut: CommandRegistry.shortcut("tabs.copyLink")) {
                    self.copyLink()
                },
                PaletteCommand(id: "tab.copy.markdown", title: "Copy as Markdown Link", symbol: "text.badge.plus", keywords: ["url", "md"], shortcut: CommandRegistry.shortcut("tabs.copyMarkdownLink")) {
                    self.copyLink(asMarkdown: true)
                },
                PaletteCommand(id: "tab.pin", title: isPinned ? "Unpin Tab" : "Pin Tab", symbol: isPinned ? "pin.slash" : "pin", shortcut: CommandRegistry.shortcut("tabs.togglePin")) {
                    self.togglePin(tab)
                },
                PaletteCommand(id: "tab.mute", title: tab.isMuted ? "Unmute Tab" : "Mute Tab", symbol: tab.isMuted ? "speaker.wave.2" : "speaker.slash", keywords: ["sound", "audio", "silence"]) {
                    tab.toggleMute()
                },
                PaletteCommand(id: "reader", title: reader == nil ? "Show Reader" : "Hide Reader", symbol: "doc.plaintext", keywords: ["article", "read"], shortcut: CommandRegistry.shortcut("view.reader")) {
                    self.toggleReader()
                },
                PaletteCommand(id: "capture", title: "Capture", symbol: "camera.viewfinder", keywords: ["screenshot", "area", "image"], shortcut: CommandRegistry.shortcut("file.capture")) {
                    self.beginCapture(of: tab)
                },
                PaletteCommand(id: "print", title: "Print Page", symbol: "printer", shortcut: CommandRegistry.shortcut("file.print")) {
                    tab.printPage()
                },
                PaletteCommand(id: "pdf", title: "Export as PDF", symbol: "doc.richtext", keywords: ["save", "pdf"]) {
                    tab.exportPDF()
                },
                PaletteCommand(id: "find", title: "Find on Page", symbol: "text.magnifyingglass", keywords: ["search"], shortcut: CommandRegistry.shortcut("edit.find")) {
                    self.showFindBar()
                },
                PaletteCommand(id: "hide.items", title: "Hide Distracting Items", symbol: "eye.slash", keywords: ["zap", "remove", "annoying", "clutter", "banner"]) {
                    self.beginHidingItems(on: tab)
                },
                PaletteCommand(
                    id: "site.blocking",
                    title: contentBlocker.isPaused(on: tab.url, privateID: tab.profile.privateID) ? "Resume Blocking on This Site" : "Pause Blocking on This Site",
                    symbol: "shield.slash", keywords: ["adblock", "broken"]
                ) {
                    self.toggleBlockingOnCurrentSite()
                },
            ]
            if recentSplitPartner != nil {
                commands.append(PaletteCommand(id: "tab.split", title: "Split with Recent Tab", symbol: "rectangle.split.2x1",
                                               keywords: ["side by side"], shortcut: CommandRegistry.shortcut("view.splitWithRecentTab")) {
                    self.splitWithRecentTab()
                })
            }
        }
        if isPrivate {
            commands.removeAll { ["folder.new", "tab.pin"].contains($0.id) }
        }
        commands += spaces.enumerated().filter { $0.element.id != activeSpaceID }.map { index, space in
            PaletteCommand(
                id: "space.\(space.id)", title: "Switch to \(space.name)", symbol: space.symbol, keywords: ["space"],
                shortcut: index < 9 ? "⌃\(index + 1)" : nil
            ) {
                self.switchTo(space)
            }
        }
        return commands
    }

    /// Commands whose title or keywords contain every typed word as a word
    /// prefix; then anything else in the menus, so whatever you can click
    /// you can also type.
    func commands(matching query: String) -> [PaletteCommand] {
        let words = query.lowercased().split(separator: " ")
        guard let first = words.first, first.count >= 2 else { return [] }
        return Self.commands(matching: query, curated: paletteCommands, fromMenus: menuCommands())
    }

    /// The curated commands, then menu commands they don't already cover
    /// (by title or shortcut), that match every typed word.
    static func commands(matching query: String, curated: [PaletteCommand], fromMenus: [PaletteCommand]) -> [PaletteCommand] {
        let words = query.lowercased().split(separator: " ")
        guard let first = words.first, first.count >= 2 else { return [] }
        let titles = Set(curated.map { $0.title.lowercased() })
        let shortcuts = Set(curated.compactMap(\.shortcut))
        let fromMenus = fromMenus.filter { !titles.contains($0.title.lowercased()) && !($0.shortcut.map(shortcuts.contains) ?? false) }
        return (curated + fromMenus).filter { command in
            let haystack = ([command.title] + command.keywords).joined(separator: " ").lowercased().split(separator: " ")
            return words.allSatisfy { word in haystack.contains { $0.hasPrefix(word) } }
        }
    }

    private func menuCommands() -> [PaletteCommand] {
        // Typing asks on every keystroke (several times per render).
        if let cache = app.menuCommandCache, Date.now.timeIntervalSince(cache.time) < 1 { return cache.commands }
        guard let mainMenu = NSApp.mainMenu else { return [] }
        let commands = Self.menuCommands(in: mainMenu, canRun: { [app] in $0.canRun(in: app) }, perform: { [app] in $0.perform(in: app) })
        app.menuCommandCache = (.now, commands)
        return commands
    }

    /// The main menu's enabled items as commands, in menu order, named after
    /// their menu ("View" for Actual Size) so either word finds them. Ours
    /// come from their registry `Command`; AppKit's own (see `ownCommand`)
    /// are read off the menu, which validates them.
    static func menuCommands(
        in mainMenu: NSMenu, canRun: (Command) -> Bool, perform: @escaping @MainActor (Command) -> Void
    ) -> [PaletteCommand] {
        var commands: [PaletteCommand] = []
        func collect(_ menu: NSMenu, path: [String]) {
            menu.refresh()
            for item in menu.items where !item.isSeparatorItem && !item.isHidden {
                if let submenu = item.submenu {
                    // Services are other apps' commands.
                    guard submenu !== NSApp.servicesMenu else { continue }
                    collect(submenu, path: path + [item.title])
                    continue
                }
                let run: @MainActor () -> Void
                if let command = item.ownCommand {
                    guard canRun(command) else { continue }
                    run = { perform(command) }
                } else {
                    // The window list's entries aren't commands, and text editing
                    // would act on the command bar's own field.
                    guard item.isEnabled, let action = item.action, action != #selector(NSWindow.makeKeyAndOrderFront(_:)),
                          !textEditingActions.contains(action)
                    else { continue }
                    run = { [titles = path + [item.title]] in performMenuItem(titled: titles) }
                }
                let title = (item.ownCommand?.title ?? item.title).replacingOccurrences(of: "…", with: "").trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { continue }
                commands.append(PaletteCommand(
                    // By menu path, not command id: what the command bar
                    // learned you pick is kept under these.
                    id: "menu.\((path + [title]).joined(separator: "."))",
                    title: title,
                    symbol: "filemenu.and.selection",
                    keywords: path.filter { !$0.isEmpty },
                    shortcut: item.shortcutLabel,
                    perform: run
                ))
            }
        }
        for item in mainMenu.items {
            if let submenu = item.submenu { collect(submenu, path: [item.title]) }
        }
        return commands
    }

    /// Found again by its titles when chosen, not kept: AppKit may have
    /// replaced or retitled it since.
    private static func performMenuItem(titled titles: [String]) {
        guard var menu = NSApp.mainMenu, let title = titles.last else { return }
        for parent in titles.dropLast() {
            guard let submenu = menu.items.first(where: { $0.title == parent })?.submenu else { return }
            menu = submenu
            menu.refresh()
        }
        let index = menu.indexOfItem(withTitle: title)
        guard index >= 0, menu.items[index].isEnabled else { return }
        menu.performActionForItem(at: index)
    }

    private static let textEditingActions: Set<Selector> = [
        #selector(NSText.cut(_:)), #selector(NSText.copy(_:)), #selector(NSText.paste(_:)),
        #selector(NSTextView.pasteAsPlainText(_:)), #selector(NSText.selectAll(_:)), #selector(NSText.delete(_:)),
        Selector(("undo:")), Selector(("redo:")),
    ]
}

@MainActor
private extension NSMenu {
    /// Builds the items of a menu that makes them on demand (Spaces) and
    /// validates them, so the list and isEnabled are current.
    func refresh() {
        delegate?.menuNeedsUpdate?(self)
        update()
    }
}
