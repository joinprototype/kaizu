import AppKit
import Testing
@testable import Kaizu

/// AppKit copies menu items now and then (Enter Full Screen's alternate,
/// for one). Our subclasses used to trap when copied; copies now keep what
/// they run.
@MainActor
struct MenuCopyTests {
    @Test func theWholeMenuBarCopies() throws {
        _ = NSApplication.shared
        let menu = MainMenu.make(app: nil)
        let copy = try #require(menu.copy() as? NSMenu)
        #expect(titles(copy) == titles(menu))
        let commands = items(menu).compactMap(\.ownCommand?.id)
        #expect(!commands.isEmpty)
        #expect(items(copy).compactMap(\.ownCommand?.id) == commands)
        // Each copy answers for itself, not for the item it came from.
        for item in items(copy) where item is CommandMenuItem {
            #expect(item.target === item)
        }
    }

    @Test func actionItemCopiesRunTheirClosure() throws {
        var runs = 0
        let item = ActionMenuItem("Count", isOn: { runs > 0 }) { runs += 1 }
        let copy = try #require(item.copy() as? ActionMenuItem)
        #expect(copy.title == "Count" && copy.target === copy)
        _ = (copy.target as AnyObject).perform(copy.action)
        #expect(runs == 1)
        #expect(copy.validateMenuItem(copy) && copy.state == .on)
    }

    @Test func dynamicMenusCopyAsDynamicMenus() throws {
        let menu = DynamicMenu(title: "Spaces", app: nil) { _ in [] }
        let copy = try #require(menu.copy() as? DynamicMenu)
        #expect(copy.title == "Spaces" && copy.delegate === copy)
    }

    private func items(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(items) ?? []) }
    }

    private func titles(_ menu: NSMenu) -> [String] {
        items(menu).map(\.title)
    }
}
