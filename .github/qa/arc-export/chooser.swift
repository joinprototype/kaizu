import AppKit
import ApplicationServices

guard ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted", AXIsProcessTrusted() else { exit(2) }
let path = CommandLine.arguments[1]
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
func button(_ title: String) -> AXUIElement {
    for _ in 0..<50 {
        if let result = controls().first(where: { e in
            attr(e,kAXRoleAttribute) as? String == "AXButton" && (attr(e,kAXTitleAttribute) as? String)?.lowercased() == title.lowercased()
        }) { return result }
        Thread.sleep(forTimeInterval:0.2)
    }
    print("Missing",title,"buttons:",controls().filter { attr($0,kAXRoleAttribute) as? String == "AXButton" }.compactMap { attr($0,kAXTitleAttribute) as? String })
    exit(3)
}
func key(_ code: CGKeyCode, _ flags: CGEventFlags = []) {
    for down in [true,false] {
        let ev=CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:down)!
        ev.flags=flags; ev.postToPid(app.processIdentifier)
    }
    Thread.sleep(forTimeInterval:0.7)
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
let apply = button("Import 7 Tabs")
print("Arc export file picker and 7-tab preview verified.")
_ = AXUIElementPerformAction(apply,kAXPressAction as CFString)
Thread.sleep(forTimeInterval:2)
