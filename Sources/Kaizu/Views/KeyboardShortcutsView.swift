import AppKit
import SwiftUI

/// Help ▸ Keyboard Shortcuts: a card of every shortcut, read from the menus
/// when it opens, so it can't fall out of date.
struct KeyboardShortcutsView: View {
    @Environment(\.colorScheme) private var scheme

    private struct Shortcut: Identifiable {
        var id: String { name }
        let name: String
        let keys: String
    }

    private struct Group: Identifiable {
        var id: String { title }
        let title: String
        let shortcuts: [Shortcut]
    }

    private let groups: [Group] = (NSApp.mainMenu?.items ?? []).compactMap { item in
        guard let menu = item.submenu else { return nil }
        menu.delegate?.menuNeedsUpdate?(menu)
        let shortcuts = menu.items.compactMap { entry -> Shortcut? in
            guard !entry.isHidden, let keys = BrowserStore.shortcut(of: entry) else { return nil }
            return Shortcut(name: entry.title.replacingOccurrences(of: "…", with: ""), keys: keys)
        }
        return shortcuts.isEmpty ? nil : Group(title: menu.title, shortcuts: shortcuts)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 32, alignment: .top), count: 2)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Keyboard Shortcuts")
                    .font(Typeface.display(34))
                    .foregroundStyle(Ink.iron(scheme))
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.title)
                                .font(Typeface.water(19))
                                .foregroundStyle(Ink.claret(scheme))
                            ForEach(group.shortcuts) { shortcut in
                                HStack {
                                    Text(shortcut.name)
                                        .font(.system(size: 13))
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    KeyCap(keys: shortcut.keys, size: 11)
                                }
                            }
                        }
                    }
                }
            }
            .padding(36)
        }
        .background(Surface.paper(scheme))
        .overlay {
            Neatline(cornerRadius: 5)
                .padding(10)
        }
        .frame(width: 720, height: 640)
    }
}
