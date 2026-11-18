import AppKit
import ApplicationServices

guard ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted", AXIsProcessTrusted() else { exit(2) }
guard CommandLine.arguments.count == 4 else { exit(2) }
let (path, expected, action) = (CommandLine.arguments[1], CommandLine.arguments[2], CommandLine.arguments[3])
let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.joinprototype.kaizu").first!
app.activate()
let source = AXUIElementCreateApplication(app.processIdentifier)
func attr(_ e: AXUIElement, _ key: String) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, key as CFString, &value) == .success else { return nil }
    return value
}
func items(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    guard depth < 18, attr(element,kAXRoleAttribute) as? String != "AXWebArea" else { return [] }
    return [element] + (attr(element,kAXChildrenAttribute) as? [AXUIElement] ?? []).flatMap { items($0,depth:depth+1) }
}
func controls() -> [AXUIElement] { (attr(source,kAXWindowsAttribute) as? [AXUIElement] ?? []).flatMap { items($0) } }
func labels(_ el: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { attr(el,$0) as? String }
}
func button(_ title: String) -> AXUIElement {
    for _ in 0..<50 {
        if let result = controls().first(where: { e in
            attr(e,kAXRoleAttribute) as? String == "AXButton" && labels(e).contains { $0.caseInsensitiveCompare(title) == .orderedSame }
        }) { return result }
        Thread.sleep(forTimeInterval:0.2)
    }
    print("Missing",title,"controls:",controls().map { [attr($0,kAXRoleAttribute) as? String ?? ""] + labels($0) }.filter { $0.count > 1 })
    exit(3)
}
func key(_ code: CGKeyCode, _ flags: CGEventFlags = []) {
    for down in [true,false] {
        let ev=CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:down)!
        ev.flags=flags; ev.postToPid(app.processIdentifier)
    }
    Thread.sleep(forTimeInterval:0.7)
}
if action == "undo" {
    guard AXUIElementPerformAction(button("Undo"), kAXPressAction as CFString) == .success else { exit(5) }
    exit(0)
}
let chooser = button("Choose File…")
AXUIElementSetMessagingTimeout(chooser,1)
_ = AXUIElementPerformAction(chooser,kAXPressAction as CFString)
Thread.sleep(forTimeInterval:1)
key(5,[.maskCommand,.maskShift])
NSPasteboard.general.clearContents()
NSPasteboard.general.setString(path,forType:.string)
key(9,.maskCommand)
key(36)
let open = button("Open")
_ = AXUIElementPerformAction(open,kAXPressAction as CFString)
let preview = button(expected)
if expected == "Nothing New" {
    guard (attr(preview, kAXEnabledAttribute) as? Bool) == false else { exit(6) }
}
let control = action == "apply" ? preview : button("Cancel")
guard AXUIElementPerformAction(control, kAXPressAction as CFString) == .success else { exit(7) }
print("Verified preview:", expected, "action:", action)
