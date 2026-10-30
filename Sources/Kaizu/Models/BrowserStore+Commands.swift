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
            PaletteCommand(id: "settings", title: "Open Settings", symbol: "gearshape", keywords: ["preferences"], shortcut: "⌘,") {
                UtilityWindows.showSettings(store: self)
            },
            PaletteCommand(id: "space.new", title: "New Space", symbol: "plus.square.on.square", keywords: ["profile"], shortcut: "⇧⌘N") {
                self.beginNewSpace()
            },
            PaletteCommand(id: "sidebar", title: "Toggle Sidebar", symbol: "sidebar.left", keywords: ["hide", "show"], shortcut: "⌘S") {
                self.toggleSidebar()
            },
            PaletteCommand(id: "little", title: "New Little Window", symbol: "macwindow", shortcut: "⌥⌘N") {
                self.openLittleWindow()
            },
            PaletteCommand(id: "private", title: "New Private Window", symbol: "eyeglasses", keywords: ["incognito"], shortcut: "⇧⌘P") {
                self.openPrivateWindow()
            },
            PaletteCommand(id: "history.show", title: "Show History", symbol: "clock", shortcut: "⌘Y") {
                UtilityWindows.showHistory(store: self)
            },
            PaletteCommand(id: "folder.new", title: "New Folder", symbol: "folder.badge.plus", keywords: ["group"]) {
                self.newFolder()
            },
            PaletteCommand(id: "tab.reopen", title: "Reopen Closed Tab", symbol: "arrow.uturn.backward", keywords: ["undo"], shortcut: "⇧⌘T") {
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
                PaletteCommand(id: "tab.copy", title: "Copy Link", symbol: "link", keywords: ["url", "share"], shortcut: "⇧⌘C") {
                    self.copyLink()
                },
                PaletteCommand(id: "tab.copy.markdown", title: "Copy as Markdown Link", symbol: "text.badge.plus", keywords: ["url", "md"], shortcut: "⌥⇧⌘C") {
                    self.copyLink(asMarkdown: true)
                },
                PaletteCommand(id: "tab.pin", title: isPinned ? "Unpin Tab" : "Pin Tab", symbol: isPinned ? "pin.slash" : "pin", shortcut: "⌘D") {
                    self.togglePin(tab)
                },
                PaletteCommand(id: "tab.split", title: "Split with Recent Tab", symbol: "rectangle.split.2x1", keywords: ["side by side"], shortcut: "⌃⇧=") {
                    self.splitWithRecentTab()
                },
                PaletteCommand(id: "tab.mute", title: tab.isMuted ? "Unmute Tab" : "Mute Tab", symbol: tab.isMuted ? "speaker.wave.2" : "speaker.slash", keywords: ["sound", "audio", "silence"]) {
                    tab.toggleMute()
                },
                PaletteCommand(id: "reader", title: reader == nil ? "Show Reader" : "Hide Reader", symbol: "doc.plaintext", keywords: ["article", "read"], shortcut: "⇧⌘R") {
                    self.toggleReader()
                },
                PaletteCommand(id: "capture", title: "Capture", symbol: "camera.viewfinder", keywords: ["screenshot", "area", "image"], shortcut: "⇧⌘2") {
                    self.beginCapture(of: tab)
                },
                PaletteCommand(id: "print", title: "Print Page", symbol: "printer", shortcut: "⌘P") {
                    tab.printPage()
                },
                PaletteCommand(id: "pdf", title: "Export as PDF", symbol: "doc.richtext", keywords: ["save", "pdf"]) {
                    tab.exportPDF()
                },
                PaletteCommand(id: "find", title: "Find on Page", symbol: "text.magnifyingglass", keywords: ["search"], shortcut: "⌘F") {
                    self.showFindBar()
                },
                PaletteCommand(id: "hide.items", title: "Hide Distracting Items", symbol: "eye.slash", keywords: ["zap", "remove", "annoying", "clutter", "banner"]) {
                    self.beginHidingItems(on: tab)
                },
                PaletteCommand(
                    id: "site.blocking",
                    title: contentBlocker.isPaused(on: tab.url) ? "Resume Blocking on This Site" : "Pause Blocking on This Site",
                    symbol: "shield.slash", keywords: ["adblock", "broken"]
                ) {
                    self.toggleBlockingOnCurrentSite()
                },
            ]
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
        let curated = paletteCommands
        let titles = Set(curated.map { $0.title.lowercased() })
        let shortcuts = Set(curated.compactMap(\.shortcut))
        let fromMenus = menuCommands().filter { !titles.contains($0.title.lowercased()) && !($0.shortcut.map(shortcuts.contains) ?? false) }
        return (curated + fromMenus).filter { command in
            let haystack = ([command.title] + command.keywords).joined(separator: " ").lowercased().split(separator: " ")
            return words.allSatisfy { word in haystack.contains { $0.hasPrefix(word) } }
        }
    }

    /// The main menu's enabled items as commands, named after their menu
    /// ("View" for Actual Size) so either word finds them.
    private func menuCommands() -> [PaletteCommand] {
        // Typing asks on every keystroke (several times per render).
        if let cache = menuCommandCache, Date.now.timeIntervalSince(cache.time) < 1 { return cache.commands }
        guard let mainMenu = NSApp.mainMenu else { return [] }
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
                // The window list's entries aren't commands, and text editing
                // would act on the command bar's own field.
                guard item.isEnabled, let action = item.action, action != #selector(NSWindow.makeKeyAndOrderFront(_:)),
                      !Self.textEditingActions.contains(action)
                else { continue }
                let title = item.title.replacingOccurrences(of: "…", with: "").trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { continue }
                commands.append(PaletteCommand(
                    id: "menu.\((path + [title]).joined(separator: "."))",
                    title: title,
                    symbol: "filemenu.and.selection",
                    keywords: path.filter { !$0.isEmpty },
                    shortcut: Self.shortcut(of: item)
                ) { [titles = path + [item.title]] in
                    Self.performMenuItem(titled: titles)
                })
            }
        }
        for item in mainMenu.items {
            if let submenu = item.submenu { collect(submenu, path: [item.title]) }
        }
        menuCommandCache = (.now, commands)
        return commands
    }

    /// Found again by its titles when chosen, not kept: some menus (Spaces)
    /// rebuild their items each time they're updated.
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

    /// "⇧⌘T" for a menu item's key equivalent.
    private static func shortcut(of item: NSMenuItem) -> String? {
        guard !item.keyEquivalent.isEmpty else { return nil }
        let modifiers = item.keyEquivalentModifierMask
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        let keys: [String: String] = ["\t": "⇥", "\r": "↩", "\u{1b}": "esc", " ": "Space"]
        return text + (keys[item.keyEquivalent] ?? item.keyEquivalent.uppercased())
    }
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
