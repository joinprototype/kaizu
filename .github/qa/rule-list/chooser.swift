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
func labels(_ el: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { attr(el,$0) as? String }
}
func control(_ title: String, roles: Set<String> = ["AXButton"]) -> AXUIElement {
    for _ in 0..<50 {
        if let result = controls().first(where: { e in
            roles.contains(attr(e,kAXRoleAttribute) as? String ?? "") && labels(e).contains { $0.caseInsensitiveCompare(title) == .orderedSame }
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
func press(_ item: AXUIElement) {
    // A modal panel can outlive the accessibility response on the calling thread.
    AXUIElementSetMessagingTimeout(item, 1)
    let result = AXUIElementPerformAction(item,kAXPressAction as CFString)
    guard result == .success || result == .cannotComplete else { print("Press failed", result.rawValue); exit(4) }
}
press(control("Privacy", roles: ["AXRadioButton","AXButton","AXTab","AXCheckBox"]))
let picker = control("Import Rule List…")
press(picker)
Thread.sleep(forTimeInterval:1)
key(5,[.maskCommand,.maskShift])
NSPasteboard.general.clearContents()
NSPasteboard.general.setString(path,forType:.string)
key(9,.maskCommand)
key(36)
press(control("Import"))
_ = control("Remove")
print("Selected the rule JSON through Settings → Privacy and the native panel.")
