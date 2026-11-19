import AppKit
import DesignSystem
import SwiftUI

/// Where a page picked in the command bar opens, by the keys held:
/// ↩ as the bar was opened for, ⌘↩ a tab in the background, ⌥↩ beside the
/// current page in a split.
nonisolated enum CommandBarTarget: Equatable {
    case usual, background, split

    init(_ flags: NSEvent.ModifierFlags) {
        switch flags.intersection([.command, .shift, .option, .control]) {
        case .command: self = .background
        case .option: self = .split
        default: self = .usual
        }
    }
}

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

    func perform(_ suggestion: Suggestion, mode: CommandBarMode, target: CommandBarTarget = .usual) {
        // Over another app there's no tab strip or split to put it in.
        let target = mode == .quick ? .usual : target
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
                open(url, mode: mode, target: target)
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
            open(entry.url, mode: mode, target: target)
        case .url(let url):
            open(url, mode: mode, target: target)
        case .search(let query):
            if let url = settings.searchEngine.searchURL(for: query) {
                open(url, mode: mode, target: target)
            }
        }
    }

    private func open(_ url: URL, mode: CommandBarMode, target: CommandBarTarget) {
        switch target {
        case .background:
            openTab(url, select: false)
            sounds.play(.openTab)
            showToast("Opened in the background", symbol: "plus.square.on.square")
            return focusWebView()
        case .split where selectedTab != nil && canAddSplitPane:
            addToSplit(openTab(url, select: false))
            return focusWebView()
        case .split, .usual:
            break
        }
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
