import AppKit
import Testing
@testable import Kaizu

@MainActor
struct CommandRegistryTests {
    private let profile = Profile(name: "Temporary", isPrivate: true)

    private func spaces(_ names: [String]) -> [Space] {
        names.map { Space(profile: profile, name: $0, symbol: "folder", hue: 0.5) }
    }

    private func commands(in entries: [MenuEntry]) -> [Command] {
        entries.compactMap { if case .command(let command) = $0 { command } else { nil } }
    }

    /// Static commands plus a Spaces menu long enough to run past ⌃9.
    private var everyCommand: [Command] {
        let spaces = spaces((1...11).map { "Space \($0)" })
        return CommandRegistry.mainMenu.flatMap(\.staticCommands) + commands(in: CommandRegistry.spaceEntries(spaces))
    }

    @Test func everyCommandHasAUniqueID() {
        let ids = everyCommand.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(CommandRegistry.commands.count == CommandRegistry.mainMenu.flatMap(\.staticCommands).count)
    }

    /// Key equivalents work across the whole menu bar (hidden items too), so
    /// that's the scope.
    @Test func noTwoCommandsShareAKeyEquivalent() {
        let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control, .function]
        let keys = everyCommand.compactMap { command in
            command.key.map { "\($0.modifiers.intersection(relevant).rawValue) \($0.character)" }
        }
        let duplicates = Dictionary(grouping: keys, by: { $0 }).filter { $0.value.count > 1 }.keys
        #expect(duplicates.isEmpty, "Shared key equivalents: \(duplicates.sorted())")
        #expect(keys.count == everyCommand.filter { $0.key != nil }.count)
    }

    /// The menu bar as the hand-built `MainMenu` made it before the registry
    /// (master's live menu with AppKit's own insertions taken out: Close All,
    /// AutoFill, Start Dictation, Emoji & Symbols, the window list).
    @Test func menuBarMatchesItsShapeBeforeTheRegistry() {
        _ = NSApplication.shared
        let rendered = render(MainMenu.make(app: nil)).joined(separator: "\n")
        #expect(rendered == Self.snapshot)
    }

    @Test func spacesMenuListsSpacesThenItsActions() {
        let entries = CommandRegistry.spaceEntries(spaces(["Personal", "Work"]))
        let lines = entries.map { entry -> String in
            guard case .command(let command) = entry else { return "---" }
            return command.title + (command.key.map { " | " + $0.label } ?? "")
        }
        #expect(lines == ["Personal | ⌃1", "Work | ⌃2", "---", "New Space…", "Edit Current Space…"])
        let tenth = commands(in: CommandRegistry.spaceEntries(spaces((1...10).map { "Space \($0)" })))[9]
        #expect(tenth.title == "Space 10" && tenth.key == nil)
    }

    /// The command bar's hints for curated commands now come from the
    /// registry; these are the literals they replaced.
    @Test func curatedShortcutHintsAreUnchanged() {
        let hints = [
            "app.settings": "⌘,", "file.newSpace": "⇧⌘N", "view.toggleSidebar": "⌘S", "file.newWindow": "⌘N",
            "file.newLittleWindow": "⌥⌘N", "file.newPrivateWindow": "⇧⌘P", "history.showAll": "⌘Y",
            "file.reopenClosedTab": "⇧⌘T", "tabs.copyLink": "⇧⌘C", "tabs.copyMarkdownLink": "⌥⇧⌘C",
            "tabs.togglePin": "⌘D", "view.reader": "⇧⌘R", "file.capture": "⇧⌘2", "file.print": "⌘P",
            "edit.find": "⌘F", "view.splitWithRecentTab": "⌃⇧=",
        ]
        for (id, hint) in hints {
            #expect(CommandRegistry.shortcut(id) == hint, "\(id)")
        }
    }

    /// What `KAIZU_DEBUG=commands` logged on master for these queries, for
    /// the menu's part (the Spaces menu needs an app, so it's empty here).
    @Test func commandBarFindsTheSameMenuCommands() {
        _ = NSApplication.shared
        let menu = MainMenu.make(app: nil)
        // With no app, a command counts as available unless it asks.
        let fromMenus = BrowserStore.menuCommands(in: menu, canRun: { $0.isEnabled == nil }, perform: { _ in })
        func curated(_ id: String, _ title: String, _ shortcut: String? = nil) -> PaletteCommand {
            PaletteCommand(id: id, title: title, symbol: "", shortcut: shortcut) {}
        }
        let curated = [
            curated("space.new", "New Space", CommandRegistry.shortcut("file.newSpace")),
            curated("window.new", "New Window", CommandRegistry.shortcut("file.newWindow")),
            curated("little", "New Little Window", CommandRegistry.shortcut("file.newLittleWindow")),
            curated("private", "New Private Window", CommandRegistry.shortcut("file.newPrivateWindow")),
            curated("folder.new", "New Folder"),
        ]
        func found(_ query: String) -> [String] {
            BrowserStore.commands(matching: query, curated: curated, fromMenus: fromMenus).map {
                "\($0.id) | \($0.title) | \($0.keywords) | \($0.shortcut ?? "")"
            }
        }
        #expect(found("split") == ["menu.View.Close Split View | Close Split View | [\"View\"] | "])
        #expect(found("new") == [
            "space.new | New Space | [] | ⇧⌘N",
            "window.new | New Window | [] | ⌘N",
            "little | New Little Window | [] | ⌥⌘N",
            "private | New Private Window | [] | ⇧⌘P",
            "folder.new | New Folder | [] | ",
            "menu.File.New Tab | New Tab | [\"File\"] | ⌘T",
        ])
        #expect(found("space") == ["space.new | New Space | [] | ⇧⌘N"])
        #expect(found("reader") == ["menu.View.Show Reader | Show Reader | [\"View\"] | ⇧⌘R"])
        #expect(found("import") == [
            "menu.File.Import from Arc | Import from Arc | [\"File\"] | ",
            "menu.File.Import Browsing Data | Import Browsing Data | [\"File\"] | ",
        ])
        #expect(found("n").isEmpty)
    }

    private func render(_ menu: NSMenu, depth: Int = 0) -> [String] {
        menu.items.flatMap { item -> [String] in
            let indent = String(repeating: "  ", count: depth)
            if item.isSeparatorItem { return [indent + "---"] }
            if let submenu = item.submenu { return [indent + item.title + " ▸"] + render(submenu, depth: depth + 1) }
            var line = indent + item.title
            if !item.keyEquivalent.isEmpty {
                let modifiers = item.keyEquivalentModifierMask
                var keys = ""
                if modifiers.contains(.control) { keys += "⌃" }
                if modifiers.contains(.option) { keys += "⌥" }
                if modifiers.contains(.shift) { keys += "⇧" }
                if modifiers.contains(.command) { keys += "⌘" }
                let names = ["\t": "⇥", "\u{F700}": "↑", "\u{F701}": "↓"]
                line += " | " + keys + (names[item.keyEquivalent] ?? item.keyEquivalent.uppercased())
            }
            if item.isHidden { line += " (hidden)" }
            return [line]
        }
    }

    #if DEBUG
    private static let debugMenu = "Debug ▸\n  Cookie Pop-up Result\n"
    #else
    private static let debugMenu = ""
    #endif

    private static let snapshot = """
    Kaizu ▸
      About Kaizu
      Check for Updates…
      ---
      Settings… | ⌘,
      ---
      Hide Kaizu | ⌘H
      Hide Others | ⌥⌘H
      Show All
      ---
      Quit Kaizu | ⌘Q
    File ▸
      New Tab | ⌘T
      New Window | ⌘N
      Open Location… | ⌘L
      Reopen Closed Tab | ⇧⌘T
      New Little Window | ⌥⌘N
      New Private Window | ⇧⌘P
      Open Little Window in Kaizu | ⌘O
      ---
      New Space… | ⇧⌘N
      Import from Arc…
      Import Browsing Data…
      ---
      Capture… | ⇧⌘2
      Export as PDF…
      Print… | ⌘P
      ---
      Close Tab | ⌘W
      Close Window | ⇧⌘W
    Edit ▸
      Undo | ⌘Z
      Redo | ⇧⌘Z
      ---
      Cut | ⌘X
      Copy | ⌘C
      Paste | ⌘V
      Paste and Match Style | ⌥⇧⌘V
      Delete
      Select All | ⌘A
      ---
      Fill from Passwords… | ⌥⌘\\
      ---
      Spelling and Grammar ▸
        Show Spelling and Grammar | ⌘:
        Check Document Now | ⌘;
        ---
        Check Spelling While Typing
        Check Grammar With Spelling
        Correct Spelling Automatically
      ---
      Find… | ⌘F
      Find Next | ⌘G
      Find Previous | ⇧⌘G
    View ▸
      Toggle Sidebar | ⌘S
      Show Reader | ⇧⌘R
      Split with Recent Tab | ⌃⇧=
      Close Split View
      ---
      Block Ads & Trackers
      Pause Blocking on This Site
      Auto-Reject Cookie Pop-ups
      Hide Distracting Items…
      Watch Part of Page…
      ---
      Reload Page | ⌘R
      Reload Ignoring Cache | ⌥⌘R
      Stop | ⌘.
      ---
      Zoom In | ⌘=
      Zoom Out | ⌘-
      Actual Size | ⌘0
      ---
      Enter Full Screen | ⌃⌘F
    History ▸
      Back | ⌘[
      Forward | ⌘]
      ---
      Show All History | ⌘Y
      Recently Archived Tabs…
      Clear History…
    Tabs ▸
      Recent Tabs | ⌃⇥
      Next Tab | ⌥⌘↓
      Previous Tab | ⌥⌘↑
      ---
      Pin / Unpin Tab | ⌘D
      Copy Link | ⇧⌘C
      Copy as Markdown Link | ⌥⇧⌘C
      Select Tab 1 | ⌘1 (hidden)
      Select Tab 2 | ⌘2 (hidden)
      Select Tab 3 | ⌘3 (hidden)
      Select Tab 4 | ⌘4 (hidden)
      Select Tab 5 | ⌘5 (hidden)
      Select Tab 6 | ⌘6 (hidden)
      Select Tab 7 | ⌘7 (hidden)
      Select Tab 8 | ⌘8 (hidden)
      Select Last Tab | ⌘9 (hidden)
    Spaces ▸
    Window ▸
      Minimize | ⌘M
      Zoom
      ---
      Bring All to Front
    \(debugMenu)Help ▸
      Keyboard Shortcuts | ⌘/
      ---
      Report a Bug…
      Report a Broken Site…
    """
}
