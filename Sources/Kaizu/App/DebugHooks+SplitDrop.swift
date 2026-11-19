#if DEBUG
import AppKit
import BrowserCore
import WebKit

/// What a page hears of a tab dragged over it, without the window server.
private final class StandInDrag: NSObject, NSDraggingInfo {
    let draggingLocation: NSPoint
    let draggingPasteboard = NSPasteboard.withUniqueName()
    let draggingDestinationWindow: NSWindow? = nil
    let draggingSourceOperationMask: NSDragOperation = .move
    let draggedImage: NSImage? = nil
    let draggingSource: Any? = nil
    let draggingSequenceNumber = 0
    let springLoadingHighlight: NSSpringLoadingHighlight = .none
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1

    var draggedImageLocation: NSPoint { draggingLocation }

    init(_ tab: UUID, at location: NSPoint) {
        draggingLocation = location
        draggingPasteboard.clearContents()
        draggingPasteboard.setData(Data(tab.uuidString.utf8), forType: .kaizuTab)
    }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    func resetSpringLoading() {}

    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
}

extension DebugHooks {
    static func qaSplitDrop(_ store: BrowserStore) {
        func check(_ name: String, _ passed: Bool) {
            log("QA split \(passed ? "ok" : "FAILED"): \(name)")
        }
        let space = store.activeSpace
        /// One pane across the top, two below, sized by hand.
        func bento(_ top: UUID, _ left: UUID, _ right: UUID) -> SplitNode {
            .group(.stacked, [
                SplitChild(node: .pane(top), share: 0.6),
                SplitChild(node: .row([left, right], shares: [0.3, 0.7]), share: 0.4),
            ])
        }
        func catcher(of tab: BrowserTab) -> NSView? {
            (tab.webView.superview as? WebContainerView)?.dropTarget
        }
        func frame(of tab: BrowserTab) -> NSRect {
            tab.webView.convert(tab.webView.bounds, to: nil)
        }
        func close(_ first: CGFloat, _ second: CGFloat) -> Bool {
            abs(first - second) < 2
        }
        let shooting = ProcessInfo.processInfo.environment["KAIZU_SHOTS"] != nil
        var shots = 0
        func shot(_ name: String) {
            guard let folder = ProcessInfo.processInfo.environment["KAIZU_SHOTS"] else { return }
            shots += 1
            saveShot(of: store.window, to: "\(folder)/\(shots)-\(name).png")
        }
        /// Drags `tab` towards that edge of `target`'s page, or right up to
        /// it for the split's own edge, shows the preview for a moment, then
        /// drops it.
        func drop(_ tab: BrowserTab, on target: BrowserTab, _ edge: SplitEdge, outer: Bool = false) async {
            guard let catcher = catcher(of: target) else { return check("the page is showing", false) }
            let box = catcher.convert(catcher.bounds, to: nil)
            let across = outer ? 10 : box.width / 4
            let down = outer ? 10 : box.height / 4
            let point = switch edge {
            case .left: NSPoint(x: box.minX + across, y: box.midY)
            case .right: NSPoint(x: box.maxX - across, y: box.midY)
            case .top: NSPoint(x: box.midX, y: box.maxY - down)
            case .bottom: NSPoint(x: box.midX, y: box.minY + down)
            }
            let drag = StandInDrag(tab.id, at: point)
            _ = catcher.draggingEntered(drag)
            // A picture needs the preview drawn; the drop doesn't.
            try? await Task.sleep(for: .seconds(shooting ? 2 : 0.3))
            shot("preview-\(edge)")
            _ = catcher.performDragOperation(drag)
            catcher.draggingEnded(drag)
            if shooting {
                try? await Task.sleep(for: .seconds(2))
            } else {
                await panesStill()
            }
            shot("dropped-\(edge)")
        }
        /// Until the panes have been where they are for a few looks in a row.
        func panesStill() async {
            try? await Task.sleep(for: .milliseconds(300))
            var last: [NSRect] = [], still = 0
            _ = await until(3) {
                let now = space.splitTabs.map(frame(of:))
                still = now == last ? still + 1 : 0
                last = now
                return still >= 3
            }
        }
        Task {
            if space.splitTabs.count == 3, space.split.count == 3 {
                let ids = space.split
                check("a bento comes back after quitting", space.splitLayout == bento(ids[0], ids[1], ids[2]))
                try? await Task.sleep(for: .seconds(3))
                logPageCount(store, "restored")
                return NSApp.terminate(nil)
            }
            if case .group(let direction, let children) = space.splitLayout, space.splitTabs.count > 1 {
                check("a split from before trees stays a row", direction == .sideBySide)
                log("QA split kept: \(children.count) panes, widths \(children.map(\.share))")
                try? await Task.sleep(for: .seconds(2))
                return NSApp.terminate(nil)
            }
            let first = store.openTab(URL(string: "https://www.swift.org/about/"))
            let second = store.openTab(URL(string: "https://example.com/"))
            let third = store.openTab(URL(string: "https://example.org/"), select: false)
            let fourth = store.openTab(URL(string: "https://example.net/"), select: false)
            let fifth = store.openTab(URL(string: "https://www.iana.org/"), select: false)
            let names = [first.id: "a", second.id: "b", third.id: "c", fourth.id: "d", fifth.id: "e"]
            let layout = { describe(space.splitLayout, names) }
            await loaded(second)

            guard let window = store.window else { return check("there's a window", false) }
            actAsFrontmost(window)
            // App Nap, out of sight, stretches a double-click into two clicks.
            let awake = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "QA")

            await drop(first, on: second, .left)
            check("left of a page sits beside it", layout() == "[a | b]")
            logPageCount(store, "side by side")

            let wide = frame(of: first)
            let gap = NSPoint(x: wide.maxX + 4, y: wide.midY)
            await mouse(in: window, at: gap, dragTo: NSPoint(x: gap.x + 60, y: gap.y))
            check("a divider drags across", await until(2) { close(frame(of: first).width, wide.width + 60) })
            shot("divider-across")
            await mouse(in: window, at: NSPoint(x: gap.x + 60, y: gap.y))
            await mouse(in: window, at: NSPoint(x: gap.x + 60, y: gap.y), clicks: 2)
            check("double-clicking it evens them out", await until(2) { close(frame(of: first).width, frame(of: second).width) })

            await drop(third, on: second, .bottom)
            check("below a pane in a row stacks just that pane", layout() == "[a | [b / c]]")
            check("the pane beside it stays as it was", close(frame(of: first).height, wide.height) && close(frame(of: first).width, wide.width))
            logPageCount(store, "bento")

            await drop(fourth, on: first, .top)
            check("each column stacks, into a grid", layout() == "[[d / a] | [b / c]]")
            check("four is the limit", catcher(of: third)?.draggingEntered(StandInDrag(fifth.id, at: .zero)) == [])
            store.split(third, with: fifth.id, at: .pane(third.id, .top))
            check("a fifth changes nothing", layout() == "[[d / a] | [b / c]]")
            check("but its panes still move", store.canSplit(third, with: second.id))
            await drop(second, on: third, .right)
            check("a pane moves and what it left closes up", layout() == "[[d / a] | c | b]")

            store.removeFromSplit(fourth)
            check("a pane leaving closes up too", layout() == "[a | c | b]")
            store.select(third)
            store.addToSplit(fourth)
            check("a pane added from the sidebar joins the end", layout() == "[a | c | b | d]")
            store.removeFromSplit(fourth)
            store.select(fifth)
            store.addToSplit(third)
            check("a split with another tab starts a row", layout() == "[e | c]")

            await drop(first, on: third, .bottom, outer: true)
            check("the bottom edge of a split takes a row across it", layout() == "[[e | c] / a]")
            check("under both panes", close(frame(of: first).width, frame(of: fifth).width + frame(of: third).width + 8))
            await drop(second, on: third, .top, outer: true)
            check("the top edge joins the rows", layout() == "[b / [e | c] / a]")
            await drop(second, on: third, .right, outer: true)
            check("a pane moves to the side of the whole split", layout() == "[[[e | c] / a] | b]")
            check("beside everything", close(frame(of: second).height, frame(of: first).height + frame(of: third).height + 8))

            store.closeSplit()
            store.select(first)
            try? await Task.sleep(for: .seconds(1))
            await drop(second, on: first, .bottom)
            check("a lone page stacks", layout() == "[a / b]")
            await drop(third, on: second, .right)
            check("one pane on top, two below", layout() == "[a / [b | c]]")

            let top = frame(of: first)
            let left = frame(of: second)
            let right = frame(of: third)
            check("the top pane spans the two below", close(top.width, left.width + right.width + 8))

            let rule = NSPoint(x: top.midX, y: top.minY - 4)
            await mouse(in: window, at: rule, dragTo: NSPoint(x: rule.x, y: rule.y - 60))
            check("the rule between rows drags down", await until(2) { close(frame(of: first).height, top.height + 60) })
            shot("divider-down")
            check("taking from both panes below", close(frame(of: second).height, left.height - 60) && close(frame(of: third).height, right.height - 60))

            let bar = NSPoint(x: left.maxX + 4, y: frame(of: second).midY)
            await mouse(in: window, at: bar, dragTo: NSPoint(x: bar.x + 40, y: bar.y))
            check("the divider between them drags across", await until(2) { close(frame(of: second).width, left.width + 40) && close(frame(of: third).width, right.width - 40) })
            check("leaving the top pane alone", close(frame(of: first).width, top.width) && close(frame(of: first).height, top.height + 60))

            await mouse(in: window, at: NSPoint(x: bar.x + 40, y: bar.y))
            await mouse(in: window, at: NSPoint(x: bar.x + 40, y: bar.y), clicks: 2)
            check("double-clicking evens its own row", await until(2) { close(frame(of: second).width, frame(of: third).width) && close(frame(of: first).height, top.height + 60) })
            let moved = NSPoint(x: rule.x, y: rule.y - 60)
            await mouse(in: window, at: moved)
            await mouse(in: window, at: moved, clicks: 2)
            check("and the rule evens the rows", await until(2) { close(frame(of: first).height, frame(of: second).height) })

            let tallest = frame(of: second).height
            await mouse(in: window, at: rule, dragTo: NSPoint(x: rule.x, y: rule.y - 2000))
            try? await Task.sleep(for: .milliseconds(300))
            check("no pane drags away to nothing", frame(of: second).height > 40 && frame(of: second).height < tallest)

            space.splitLayout = bento(first.id, second.id, third.id)
            try? await Task.sleep(for: .milliseconds(300))
            shot("bento")
            ProcessInfo.processInfo.endActivity(awake)
            NSApp.terminate(nil)
        }
    }

    /// A layout as text: `[a / [b | c]]`.
    private static func describe(_ node: SplitNode?, _ names: [UUID: String]) -> String {
        switch node {
        case nil: "none"
        case .pane(let id): names[id] ?? "?"
        case .group(let direction, let children):
            "[" + children.map { describe($0.node, names) }.joined(separator: direction == .stacked ? " / " : " | ") + "]"
        }
    }

    /// Gestures ignore the click that would activate a window, and a QA run
    /// sits behind whatever's in front. Has the app say it's active and `window`
    /// say it's key without taking focus. Just that window: AppKit's own, like
    /// the menu bar's, aren't ready to be.
    private static func actAsFrontmost(_ window: NSWindow) {
        let isKey: @convention(block) (NSWindow) -> Bool = { [weak window] in $0 === window }
        if let method = class_getInstanceMethod(NSWindow.self, #selector(getter: NSWindow.isKeyWindow)) {
            method_setImplementation(method, imp_implementationWithBlock(isKey))
        }
        let isActive: @convention(block) (NSApplication) -> Bool = { _ in true }
        if let method = class_getInstanceMethod(NSApplication.self, #selector(getter: NSApplication.isActive)) {
            method_setImplementation(method, imp_implementationWithBlock(isActive))
        }
    }

    /// A press, an optional drag and a release, through the window as the
    /// mouse's would come. A real drag between views needs the window server;
    /// this reaches gestures, which can't tell.
    private static func mouse(in window: NSWindow, at start: NSPoint, dragTo end: NSPoint? = nil, clicks: Int = 1) async {
        func send(_ type: NSEvent.EventType, _ point: NSPoint) async {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1
            ) else { return }
            window.sendEvent(event)
            try? await Task.sleep(for: .milliseconds(30))
        }
        if let end {
            // Behind other apps, a click after a pause only wakes the window.
            await send(.leftMouseDown, start)
            await send(.leftMouseUp, start)
            try? await Task.sleep(for: .milliseconds(500))
            await send(.leftMouseDown, start)
            for step in 1...10 {
                let progress = CGFloat(step) / 10
                await send(.leftMouseDragged, NSPoint(x: start.x + (end.x - start.x) * progress, y: start.y + (end.y - start.y) * progress))
            }
        } else {
            await send(.leftMouseDown, start)
        }
        await send(.leftMouseUp, end ?? start)
    }
}
#endif
