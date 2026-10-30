import AppKit
import Carbon.HIToolbox

/// Quick search from any app: the command bar over whatever you're in.
extension BrowserStore {
    /// Registers the shortcut chosen in Settings (or none), replacing the old one.
    func applyQuickBarKey() {
        quickBarHotKey?.unregister()
        quickBarHotKey = nil
        isQuickBarKeyTaken = false
        guard let key = settings.quickBarKey else {
            quickBar?.hide()
            return
        }
        quickBarHotKey = GlobalHotKey(keyCode: kVK_Space, modifiers: key.carbonModifiers) { [weak self] in
            self?.toggleQuickBar()
        }
        isQuickBarKeyTaken = quickBarHotKey == nil
    }

    /// Inside Kaizu's own window the shortcut is just ⌘T.
    func toggleQuickBar() {
        if NSApp.isActive, window?.isKeyWindow == true {
            return commandBar == nil ? showCommandBar(.newTab) : dismissCommandBar()
        }
        if quickBar == nil {
            quickBar = QuickBarController(store: self)
        }
        quickBar?.toggle()
    }
}

private extension Settings.QuickBarKey {
    var carbonModifiers: Int {
        switch self {
        case .optionSpace: optionKey
        case .shiftOptionSpace: shiftKey | optionKey
        case .controlShiftSpace: controlKey | shiftKey
        }
    }
}
