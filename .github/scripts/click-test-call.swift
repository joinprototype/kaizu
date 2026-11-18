import AppKit
import ApplicationServices

guard ProcessInfo.processInfo.environment["RUNNER_ENVIRONMENT"] == "github-hosted",
      AXIsProcessTrusted(),
      let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.joinprototype.kaizu").first else {
    exit(2)
}
app.activate()
let root = AXUIElementCreateApplication(app.processIdentifier)
func attribute(_ item: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(item, key as CFString, &value) == .success ? value : nil
}
func findButton(_ item: AXUIElement, depth: Int = 0) -> AXUIElement? {
    guard depth < 30 else { return nil }
    if attribute(item, kAXRoleAttribute) as? String == "AXButton",
       [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].contains(where: {
           attribute(item, $0) as? String == "Start Kaizu test call"
       }) { return item }
    for child in attribute(item, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let button = findButton(child, depth: depth + 1) { return button }
    }
    return nil
}
let deadline = Date().addingTimeInterval(10)
while Date() < deadline {
    if let button = findButton(root),
       let pos = attribute(button, kAXPositionAttribute), let size = attribute(button, kAXSizeAttribute),
       CFGetTypeID(pos) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
        var origin = CGPoint.zero, bounds = CGSize.zero
        guard AXValueGetValue(pos as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &bounds), bounds.width > 0, bounds.height > 0 else { exit(3) }
        let point = CGPoint(x: origin.x + bounds.width / 2, y: origin.y + bounds.height / 2)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { exit(4) }
            event.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.05)
        }
        exit(0)
    }
    Thread.sleep(forTimeInterval: 0.1)
}
exit(5)
