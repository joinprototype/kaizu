#if DEBUG
import AppKit
import BrowserCore
import DesignSystem

extension DebugHooks {
    static func qaShowcase(_ store: BrowserStore) {
        guard let folder = ProcessInfo.processInfo.environment["KAIZU_SHOTS"] else { return }
        func shoot(_ name: String) {
            guard let view = store.window?.contentView, let picture = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: picture)
            try? picture.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder).appending(path: "\(name).png"))
        }
        func tab(_ address: String, _ title: String) -> BrowserTab {
            BrowserTab(profile: store.activeSpace.profile, app: store.app, url: URL(string: address), title: title, pinnedURL: URL(string: address))
        }
        Task {
            let space = store.activeSpace
            shoot("empty-dark")
            space.appearance = .light
            store.updateWindowAppearance()
            try? await Task.sleep(for: .seconds(2))
            shoot("empty-light")

            for (address, title) in [("https://mail.google.com/", "Gmail"), ("https://calendar.google.com/", "Calendar"), ("https://github.com/", "GitHub"), ("https://www.youtube.com/", "YouTube")] {
                space.profile.favorites.append(tab(address, title))
            }
            let reading = Folder(name: "Reading", isExpanded: true, children: [
                .tab(tab("https://www.theverge.com/", "The Verge")),
                .tab(tab("https://news.ycombinator.com/", "Hacker News")),
            ])
            space.pinned = [.tab(tab("https://www.notion.so/", "Notes")), .tab(tab("https://www.figma.com/", "Figma")), .folder(reading)]
            let pages = [
                ("https://en.wikipedia.org/wiki/Nautical_chart", "Nautical chart - Wikipedia"),
                ("https://www.bbc.com/", "BBC Home"),
                ("https://stackoverflow.com/", "Newest Questions - Stack Overflow"),
                ("https://www.apple.com/", "Apple"),
            ]
            for (address, title) in pages.reversed() {
                store.openTab(URL(string: address), select: false).title = title
            }
            store.commit(SpaceDraft(name: "Work", hue: Theme.all[5].hue, symbol: Space.symbols[1], profile: .existing(space.profile.id)))
            store.commit(SpaceDraft(name: "Home", hue: Theme.all[0].hue, symbol: Space.symbols[2], profile: .existing(space.profile.id)))
            store.switchTo(space)
            for favorite in space.profile.favorites + space.pinned.tabs + space.today {
                favorite.activate()
            }
            store.select(space.today[0])
            try? await Task.sleep(for: .seconds(8))
            shoot("page-light")

            for (index, theme) in Theme.all.enumerated() where ["verdigris", "navy", "ochre"].contains(theme.id) {
                let other = store.spaces[1]
                other.hue = theme.hue
                other.appearance = index % 2 == 0 ? .dark : .light
                store.switchTo(other)
                try? await Task.sleep(for: .seconds(1.5))
                shoot("theme-\(theme.id)")
                store.switchTo(space)
                try? await Task.sleep(for: .seconds(0.6))
            }
            store.showCommandBar(.newTab)
            try? await Task.sleep(for: .seconds(1))
            shoot("commandbar-light")
            typeIntoKeyWindow("wiki")
            try? await Task.sleep(for: .seconds(1.5))
            shoot("commandbar-typed")
            store.dismissCommandBar()
            store.showToast("Pinned to \(space.name)", symbol: "pin.fill")
            try? await Task.sleep(for: .seconds(0.5))
            shoot("toast-light")

            space.appearance = .dark
            store.updateWindowAppearance()
            try? await Task.sleep(for: .seconds(2))
            shoot("page-dark")
            store.showCommandBar(.newTab)
            try? await Task.sleep(for: .seconds(1))
            shoot("commandbar-dark")
            store.dismissCommandBar()
            space.appearance = .light
            store.updateWindowAppearance()
            try? await Task.sleep(for: .seconds(1))

            store.showFindBar()
            store.updateFind("chart")
            try? await Task.sleep(for: .seconds(1))
            shoot("find")
            store.hideFindBar()
            store.advanceTabSwitcher(backwards: false)
            try? await Task.sleep(for: .seconds(1))
            shoot("switcher")
            store.commitTabSwitcher(to: 0)
            store.peek(URL(string: "https://www.bbc.com/")!, from: space.today[0])
            try? await Task.sleep(for: .seconds(3))
            shoot("peek")
            store.closePeek()
            try? await Task.sleep(for: .seconds(1))
            store.beginEditing(space)
            try? await Task.sleep(for: .seconds(1))
            saveShot(of: store.window?.attachedSheet, to: folder + "/space-editor.png")
            store.spaceDraft = nil
            try? await Task.sleep(for: .seconds(1))
            let lost = store.openTab(URL(string: "https://nonexistent.invalid/"))
            try? await Task.sleep(for: .seconds(3))
            shoot("error")
            store.close(lost)
            try? await Task.sleep(for: .seconds(2))
            store.toggleReader()
            try? await Task.sleep(for: .seconds(4))
            log("QA reader shown: \(store.reader != nil)")
            shoot("reader")
            store.closeReader()
            UtilityWindows.showAbout(app: store.app)
            try? await Task.sleep(for: .seconds(1))
            saveShot(of: NSApp.windows.first { $0.title == "About Kaizu" }, to: folder + "/about.png")
            NSApp.windows.first { $0.title == "About Kaizu" }?.close()
            UtilityWindows.showKeyboardShortcuts(app: store.app)
            try? await Task.sleep(for: .seconds(1))
            saveShot(of: NSApp.windows.first { $0.title == "Keyboard Shortcuts" }, to: folder + "/shortcuts.png")
            NSApp.windows.first { $0.title == "Keyboard Shortcuts" }?.close()
            UtilityWindows.showHistory(app: store.app)
            try? await Task.sleep(for: .seconds(1))
            saveShot(of: NSApp.windows.first { $0.title == "History" }, to: folder + "/history.png")
            NSApp.windows.first { $0.title == "History" }?.close()

            UtilityWindows.showSettings(app: store.app)
            try? await Task.sleep(for: .seconds(1))
            saveShot(of: NSApp.windows.first { $0.title == "Settings" }, to: folder + "/settings.png")
            NSApp.windows.first { $0.title == "Settings" }?.close()

            let hidden = store.app.openPrivateWindow()
            let page = hidden.openTab(URL(string: "https://www.apple.com/"))
            page.title = "Apple"
            try? await Task.sleep(for: .seconds(3))
            saveShot(of: hidden.window, to: folder + "/private.png")
            hidden.window?.performClose(nil)

            store.select(space.today[1])
            store.openLittleWindow(URL(string: "https://example.com/"))
            try? await Task.sleep(for: .seconds(2))
            saveShot(of: NSApp.keyWindow, to: folder + "/little.png")
            NSApp.terminate(nil)
        }
    }
}
#endif
