import Foundation
import Testing
@testable import BrowserCore

@Suite struct SplitLayoutTests {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    /// The layout as text: `[a / [b | c]]`.
    private func shape(_ node: SplitNode?) -> String {
        switch node {
        case nil: "none"
        case .pane(let id): [a: "a", b: "b", c: "c", d: "d"][id] ?? "?"
        case .group(let direction, let children):
            "[" + children.map { shape($0.node) }.joined(separator: direction == .stacked ? " / " : " | ") + "]"
        }
    }

    private func shares(_ node: SplitNode?) -> [Double] {
        guard case .group(_, let children) = node else { return [] }
        return children.map(\.share)
    }

    private func isClose(_ first: CGRect?, _ second: CGRect) -> Bool {
        guard let first else { return false }
        return abs(first.minX - second.minX) < 1e-6 && abs(first.minY - second.minY) < 1e-6
            && abs(first.width - second.width) < 1e-6 && abs(first.height - second.height) < 1e-6
    }

    /// One pane across the top, two below.
    private var bento: SplitNode {
        SplitNode.pane(a).placing(b, by: a, on: .bottom).placing(c, by: b, on: .right)
    }

    // MARK: Where a drop lands

    @Test(arguments: [
        (0.1, 0.5, SplitEdge.left), (0.9, 0.5, .right),
        (0.5, 0.1, .top), (0.5, 0.9, .bottom),
        // Just inside each corner, the nearer side wins.
        (0.05, 0.1, .left), (0.1, 0.05, .top),
        (0.95, 0.9, .right), (0.9, 0.95, .bottom),
    ])
    func nearestSideOfThePage(x: Double, y: Double, edge: SplitEdge) {
        #expect(SplitEdge(x: x, y: y) == edge)
    }

    /// Dragged in from the sidebar along the middle, as it always was.
    @Test func theMiddleStaysLeftAndRight() {
        #expect(SplitEdge(x: 0.49, y: 0.5) == .left)
        #expect(SplitEdge(x: 0.51, y: 0.5) == .right)
    }

    // MARK: Building a layout

    @Test func aLonePageSplitsAnyWay() {
        #expect(shape(SplitNode.pane(a).placing(b, by: a, on: .left)) == "[b | a]")
        #expect(shape(SplitNode.pane(a).placing(b, by: a, on: .right)) == "[a | b]")
        #expect(shape(SplitNode.pane(a).placing(b, by: a, on: .top)) == "[b / a]")
        #expect(shape(SplitNode.pane(a).placing(b, by: a, on: .bottom)) == "[a / b]")
    }

    @Test func aPaneOnTopWithTwoBelow() {
        #expect(shape(bento) == "[a / [b | c]]")
        #expect(bento.panes == [a, b, c])
    }

    @Test func twoColumnsOfTwo() {
        let grid = SplitNode.row([a, b]).placing(c, by: a, on: .bottom).placing(d, by: b, on: .bottom)
        #expect(shape(grid) == "[[a / c] | [b / d]]")
    }

    /// A drop halves its pane and leaves the rest as they were.
    @Test func aDropTakesHalfOfItsPane() {
        let row = SplitNode.row([a, b]).placing(c, by: b, on: .right)
        #expect(shape(row) == "[a | b | c]")
        #expect(shares(row) == [0.5, 0.25, 0.25])
        #expect(shares(row.placing(d, by: a, on: .left)) == [0.25, 0.25, 0.25, 0.25])
    }

    @Test func goingTheOtherWayNestsJustThatPane() {
        let nested = SplitNode.row([a, b]).placing(c, by: b, on: .bottom)
        #expect(shape(nested) == "[a | [b / c]]")
        #expect(shares(nested) == [0.5, 0.5])
    }

    @Test func aPaneInTheLayoutMoves() {
        #expect(shape(bento.placing(c, by: a, on: .right)) == "[[a | c] / b]")
        #expect(shape(bento.placing(a, by: c, on: .bottom)) == "[b | [c / a]]")
        #expect(shape(SplitNode.row([a, b]).placing(b, by: a, on: .top)) == "[b / a]")
    }

    @Test func aTargetThatIsntThereChangesNothing() {
        #expect(SplitNode.row([a, b]).placing(c, by: d, on: .left) == SplitNode.row([a, b]))
    }

    @Test func appendingJoinsTheTopGroup() {
        let row = SplitNode.row([a, b]).appending(c)
        #expect(shape(row) == "[a | b | c]")
        #expect(shares(row).allSatisfy { abs($0 - 1.0 / 3) < 1e-9 })
        #expect(shape(bento.appending(d)) == "[a / [b | c] / d]")
    }

    // MARK: Taking panes out

    @Test func whatsLeftTakesUpTheRoom() {
        let row = SplitNode.row([a, b, c], shares: [0.5, 0.3, 0.2]).removing(c)
        #expect(shape(row) == "[a | b]")
        #expect(abs(shares(row)[0] - 0.625) < 1e-9)
    }

    @Test func aGroupOfOneBecomesThatOne() {
        #expect(shape(bento.removing(b)) == "[a / c]")
        #expect(shape(bento.removing(a)) == "[b | c]")
        #expect(shape(SplitNode.row([a, b]).removing(a)) == "b")
        #expect(SplitNode.pane(a).removing(a) == nil)
    }

    /// Lifted up a level, a row inside a row is just a longer row.
    @Test func aPartRunningItsGroupsWayJoinsIt() {
        let wide = SplitNode.row([a, d]).placing(b, by: a, on: .bottom).placing(c, by: b, on: .right)
        #expect(shape(wide) == "[[a / [b | c]] | d]")
        let merged = wide.removing(a)
        #expect(shape(merged) == "[b | c | d]")
        #expect(shares(merged) == [0.25, 0.25, 0.5])
    }

    @Test func keepingDropsWhatsGone() {
        #expect(shape(bento.keeping([a, c])) == "[a / c]")
        #expect(SplitNode.row([a, b]).keeping([]) == nil)
    }

    // MARK: Geometry

    private let bounds = CGRect(x: 0, y: 0, width: 1008, height: 808)

    @Test func aPaneFillsTheBounds() {
        #expect(SplitNode.pane(a).geometry(in: bounds, gap: 8).panes == [a: bounds])
        #expect(SplitNode.pane(a).geometry(in: bounds, gap: 8).dividers.isEmpty)
    }

    @Test func aBentoFitsItsPanesInTheGaps() {
        let geometry = bento.geometry(in: bounds, gap: 8)
        #expect(isClose(geometry.panes[a], CGRect(x: 0, y: 0, width: 1008, height: 400)))
        #expect(isClose(geometry.panes[b], CGRect(x: 0, y: 408, width: 500, height: 400)))
        #expect(isClose(geometry.panes[c], CGRect(x: 508, y: 408, width: 500, height: 400)))
    }

    @Test func dividersFillTheGaps() {
        let dividers = bento.geometry(in: bounds, gap: 8).dividers
        #expect(dividers.count == 2)
        let rule = dividers.first { $0.direction == .stacked }
        let bar = dividers.first { $0.direction == .sideBySide }
        #expect(isClose(rule?.frame, CGRect(x: 0, y: 400, width: 1008, height: 8)))
        #expect(isClose(bar?.frame, CGRect(x: 500, y: 408, width: 8, height: 400)))
        #expect(rule?.length == 800)
        #expect(bar?.length == 1000)
        #expect(Set(dividers.map(\.id)).count == 2)
    }

    // MARK: Dividers

    @Test func aDividerMovesThePartsEitherSide() throws {
        let geometry = bento.geometry(in: bounds, gap: 8)
        let rule = try #require(geometry.dividers.first { $0.direction == .stacked })
        let moved = bento.resized(rule, by: 80).geometry(in: bounds, gap: 8)
        #expect(isClose(moved.panes[a], CGRect(x: 0, y: 0, width: 1008, height: 480)))
        #expect(moved.panes[b]?.height == 320)
        #expect(moved.panes[c]?.height == 320)
    }

    @Test func aNestedDividerLeavesTheRestAlone() throws {
        let bar = try #require(bento.geometry(in: bounds, gap: 8).dividers.first { $0.direction == .sideBySide })
        let moved = bento.resized(bar, by: 100).geometry(in: bounds, gap: 8)
        #expect(moved.panes[a]?.height == 400)
        #expect(moved.panes[b]?.width == 600)
        #expect(moved.panes[c]?.width == 400)
    }

    @Test func noPaneDragsDownToNothing() throws {
        let divider = try #require(SplitNode.row([a, b]).geometry(in: bounds, gap: 8).dividers.first)
        let row = SplitNode.row([a, b])
        #expect(shares(row.resized(divider, by: 5000)) == [0.85, 0.15000000000000002])
        #expect(shares(row.resized(divider, by: -5000)) == [0.15, 0.85])
    }

    @Test func halvedPanesStaySmallerThanTheMinimumAllows() throws {
        let row = SplitNode.row([a, b, c, d], shares: [0.7, 0.1, 0.1, 0.1])
        let divider = try #require(row.geometry(in: bounds, gap: 8).dividers.last)
        let after = shares(row.resized(divider, by: -500))
        #expect(abs(after[2] - 0.1) < 1e-9)
        #expect(abs(after[3] - 0.1) < 1e-9)
    }

    @Test func evenedActsOnItsOwnGroup() throws {
        var layout = bento
        let geometry = layout.geometry(in: bounds, gap: 8)
        let rule = try #require(geometry.dividers.first { $0.direction == .stacked })
        let bar = try #require(geometry.dividers.first { $0.direction == .sideBySide })
        layout = layout.resized(rule, by: 80).resized(bar, by: 100)
        let even = layout.evened(bar)
        #expect(even.geometry(in: bounds, gap: 8).panes[b]?.width == 500)
        #expect(even.geometry(in: bounds, gap: 8).panes[a]?.height == 480)
        #expect(even.evened(rule) == bento)
    }

    // MARK: In a session

    /// Exactly what every build has written for a row.
    @Test func aRowSavesAsWidths() {
        #expect(SplitNode.row([a, b]).saved.widths == nil)
        #expect(SplitNode.row([a, b]).saved.layout == nil)
        #expect(SplitNode.row([a, b], shares: [0.6, 0.4]).saved.widths == [0.6, 0.4])
        #expect(SplitNode.row([a, b], shares: [0.6, 0.4]).saved.layout == nil)
    }

    @Test func anythingElseSavesAsATree() {
        #expect(bento.saved.widths == nil)
        #expect(bento.saved.layout == bento)
        let stack = SplitNode.pane(a).placing(b, by: a, on: .top)
        #expect(stack.saved.layout == stack)
    }

    @Test(arguments: [0, 1, 2]) func everyLayoutComesBack(index: Int) {
        let node = [SplitNode.row([a, b], shares: [0.6, 0.4]), SplitNode.row([a, b, c]), bento][index]
        #expect(SplitNode.restored(layout: node.saved.layout, panes: node.panes, widths: node.saved.widths ?? []) == node)
    }

    @Test func aTreeSurvivesJSON() throws {
        let encoded = try JSONCoding.encoder.encode(bento)
        #expect(try JSONCoding.decoder.decode(SplitNode.self, from: encoded) == bento)
    }

    /// What every build before trees wrote.
    @Test func aFlatSplitLoadsAsARow() {
        #expect(SplitNode.restored(layout: nil, panes: [a, b], widths: [0.65, 0.35]) == .row([a, b], shares: [0.65, 0.35]))
        #expect(SplitNode.restored(layout: nil, panes: [a, b, c], widths: [0.5, 0.5]) == .row([a, b, c]))
    }

    @Test func oneLeftoverPaneIsNoSplit() {
        #expect(SplitNode.restored(layout: nil, panes: [a], widths: []) == nil)
        #expect(SplitNode.restored(layout: nil, panes: [], widths: []) == nil)
    }

    @Test func aTreeThatDisagreesWithThePanesGivesWay() {
        #expect(SplitNode.restored(layout: bento, panes: [a, b], widths: []) == .row([a, b]))
        #expect(SplitNode.restored(layout: bento, panes: [a, b, c, d], widths: []) == .row([a, b, c, d]))
    }

    /// A pane shown twice would need one web view in two places.
    @Test func aRepeatedPaneShowsOnce() {
        let doubled = SplitNode.group(.stacked, [
            SplitChild(node: .pane(a), share: 0.5),
            SplitChild(node: .row([a, b]), share: 0.5),
        ])
        #expect(shape(SplitNode.restored(layout: doubled, panes: [a, b], widths: [])) == "[a / b]")
        #expect(shape(SplitNode.restored(layout: nil, panes: [a, a, b], widths: [])) == "[a | b]")
    }

    @Test func nonsenseSharesComeBackEven() {
        let broken = SplitNode.group(.stacked, [
            SplitChild(node: .pane(a), share: -1),
            SplitChild(node: .pane(b), share: .nan),
        ])
        #expect(shares(SplitNode.restored(layout: broken, panes: [a, b], widths: [])) == [0.5, 0.5])
    }

    /// From a later build: the pane list still opens every tab.
    @Test func anUnknownLayoutCantLoseTheSession() throws {
        let unknown = #"{ "direction": "diagonal", "children": [{ "spiral": 3 }] }"#
        let decoded = try JSONCoding.decoder.decode(SplitNode.self, from: Data(unknown.utf8))
        #expect(SplitNode.restored(layout: decoded, panes: [a, b], widths: []) == .row([a, b]))
        let garbled = #"{ "children": "nope" }"#
        let other = try JSONCoding.decoder.decode(SplitNode.self, from: Data(garbled.utf8))
        #expect(SplitNode.restored(layout: other, panes: [a, b], widths: []) == .row([a, b]))
    }
}
