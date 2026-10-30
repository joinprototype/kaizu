import AppKit
import Carbon.HIToolbox

/// A shortcut that works in every app, through Carbon's hot keys: the one
/// API for this that needs no Accessibility permission.
@MainActor
final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let id: UInt32
    private let action: () -> Void
    private static var nextID: UInt32 = 1

    /// Nil when the shortcut is taken: by a system shortcut that's turned
    /// on (Spotlight, input sources…) or by another app.
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        guard !Self.isSystemShortcut(keyCode: keyCode, modifiers: modifiers) else { return nil }
        id = Self.nextID
        Self.nextID += 1
        self.action = action
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var pressedID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &pressedID
            )
            // Carbon delivers hot key events on the main thread.
            return MainActor.assumeIsolated {
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                guard pressedID.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
                hotKey.action()
                return noErr
            }
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let hotKeyID = EventHotKeyID(signature: 0x5054_4C4E, id: id)  // "PTLN"
        guard installed == noErr,
              // Exclusive, so registering fails if another app holds it.
              RegisterEventHotKey(
                UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(),
                OptionBits(kEventHotKeyExclusive), &hotKey
              ) == noErr
        else {
            unregister()
            return nil
        }
    }

    isolated deinit {
        unregister()
    }

    private static func isSystemShortcut(keyCode: Int, modifiers: Int) -> Bool {
        var shortcuts: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&shortcuts) == noErr,
              let list = shortcuts?.takeRetainedValue() as? [[String: Any]]
        else { return false }
        return list.contains { shortcut in
            shortcut[kHISymbolicHotKeyEnabled as String] as? Bool == true
                && shortcut[kHISymbolicHotKeyCode as String] as? Int == keyCode
                && shortcut[kHISymbolicHotKeyModifiers as String] as? Int == modifiers
        }
    }

    /// The event handler points at this object, so it goes first.
    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }
}
