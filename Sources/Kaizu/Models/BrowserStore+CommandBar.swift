import AppKit
import SwiftUI

enum CommandBarMode: Equatable {
    /// ⌘T: result opens in a new tab.
    case newTab
    /// ⌘L: result replaces the current tab's page.
    case currentTab
    /// The quick bar over another app: pages open in a little window.
    case quick
}

extension BrowserStore {
    // MARK: - Command bar

    func showCommandBar(_ mode: CommandBarMode) {
        window?.makeKeyAndOrderFront(nil)
        if commandBar == nil {
            sounds.play(.commandBar)
        }
        withAnimation(Motion.pop) {
            commandBar = mode
        }
    }

    func dismissCommandBar() {
        withAnimation(Motion.snap) {
            commandBar = nil
        }
        focusWebView()
    }

    func perform(_ suggestion: Suggestion, mode: CommandBarMode) {
        if mode == .quick {
            app.quickBar?.hide()
            // From the quick bar, pages get a little window; tabs, commands
            // and the archive need the main window.
            switch suggestion {
            case .command, .tab, .archived:
                window?.makeKeyAndOrderFront(nil)
                NSApp.activate()
            default: break
            }
        } else {
            withAnimation(Motion.snap) {
                commandBar = nil
            }
        }
        switch suggestion {
        case .answer(let answer):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(answer.answer, forType: .string)
            // Over another app, copying is the whole point: nothing comes forward.
            guard mode != .quick else { return }
            showToast("Copied \(answer.answer)")
            focusWebView()
        case .shortcut(let shortcut, let query):
            if let url = shortcut.url(for: query) {
                open(url, mode: mode)
            }
        case .command(let command):
            command.perform()
        case .tab(let tab, let space):
            guard space.profile === activeSpace.profile, spaces.contains(where: { $0 === space }),
                  space.tab(id: tab.id) === tab else { return }
            select(tab, in: space)
        case .archived(let archived):
            reopen(archived)
        case .history(let entry):
            open(entry.url, mode: mode)
        case .url(let url):
            open(url, mode: mode)
        case .search(let query):
            if let url = settings.searchEngine.searchURL(for: query) {
                open(url, mode: mode)
            }
        }
    }

    private func open(_ url: URL, mode: CommandBarMode) {
        switch mode {
        case .currentTab where selectedTab != nil:
            selectedTab?.load(url)
            focusWebView()
        case .quick:
            openLittleWindow(url)
            NSApp.activate()
        default:
            openTab(url)
            sounds.play(.openTab)
        }
    }
}
