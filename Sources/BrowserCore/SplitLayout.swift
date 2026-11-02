import CoreGraphics
import Foundation

/// Which way a group of panes runs.
public enum SplitDirection: String, Sendable {
    case sideBySide, stacked
}

/// The side of a page a tab dragged onto it lands on.
public enum SplitEdge: Sendable {
    case left, right, top, bottom

    /// The side nearest a point on the page, given from its top left as
    /// fractions of its size: the page's diagonals cut it into four, so a
    /// tab dragged in along the middle lands left or right as it always did.
    init(x: Double, y: Double) {
        if abs(x - 0.5) >= abs(y - 0.5) {
            self = x < 0.5 ? .left : .right
        } else {
            self = y < 0.5 ? .top : .bottom
        }
    }

    fileprivate var direction: SplitDirection {
        switch self {
        case .left, .right: .sideBySide
        case .top, .bottom: .stacked
        }
    }

    fileprivate var isBefore: Bool { self == .left || self == .top }
}

/// Where a dragged tab lands.
public enum SplitPlace: Equatable, Sendable {
    /// On one side of a pane, taking half of it.
    case pane(UUID, SplitEdge)
    /// Along one side of the whole split, taking half of that.
    case split(SplitEdge)
}

/// How a split's panes sit: a pane, or a group of these side by side or
/// stacked. Any pane can split again the other way, so panes can make any
/// bento: one across the top with two below is a stack of a pane and a row.
public indirect enum SplitNode: Equatable, Sendable {
    case pane(UUID)
    case group(SplitDirection, [SplitChild])
}

public struct SplitChild: Equatable, Sendable {
    public var node: SplitNode
    /// Its part of the group's length; a group's shares add up to 1.
    public var share: Double

    public init(node: SplitNode, share: Double) {
        self.node = node
        self.share = share
    }
}

// MARK: - Changing a layout

extension SplitNode {
    /// The least of its group a dragged divider leaves a pane.
    private static let minimumShare = 0.15

    /// `panes` side by side, with `shares` of the width if there's one for each.
    public static func row(_ panes: [UUID], shares: [Double] = []) -> SplitNode {
        let shares = shares.count == panes.count ? shares : Array(repeating: 1 / Double(panes.count), count: panes.count)
        return .group(.sideBySide, zip(panes, shares).map { SplitChild(node: .pane($0), share: $1) })
    }

    /// The panes, top left first.
    public var panes: [UUID] {
        switch self {
        case .pane(let id): [id]
        case .group(_, let children): children.flatMap(\.node.panes)
        }
    }

    public func placing(_ id: UUID, at place: SplitPlace) -> SplitNode {
        switch place {
        case .pane(let target, let edge): placing(id, by: target, on: edge)
        case .split(let edge): placing(id, along: edge)
        }
    }

    /// With `id` taking half of `target`'s place, on `edge`. If it's already
    /// here it moves there, and what it leaves closes up.
    func placing(_ id: UUID, by target: UUID, on edge: SplitEdge) -> SplitNode {
        (removing(id) ?? self).splitting(target, with: id, on: edge)
    }

    /// With `id` taking half of the whole layout, along `edge`.
    func placing(_ id: UUID, along edge: SplitEdge) -> SplitNode {
        let halves = [removing(id) ?? self, .pane(id)].map { SplitChild(node: $0, share: 0.5) }
        return Self.tidied(edge.direction, edge.isBefore ? halves.reversed() : halves) ?? self
    }

    private func splitting(_ target: UUID, with id: UUID, on edge: SplitEdge) -> SplitNode {
        switch self {
        case .pane(target):
            let panes = edge.isBefore ? [id, target] : [target, id]
            return .group(edge.direction, panes.map { SplitChild(node: .pane($0), share: 0.5) })
        case .pane:
            return self
        case .group(let direction, var children):
            if direction == edge.direction, let index = children.firstIndex(where: { $0.node == .pane(target) }) {
                children[index].share /= 2
                let half = SplitChild(node: .pane(id), share: children[index].share)
                children.insert(half, at: edge.isBefore ? index : index + 1)
            } else {
                for index in children.indices {
                    children[index].node = children[index].node.splitting(target, with: id, on: edge)
                }
            }
            return .group(direction, children)
        }
    }

    /// With `id` joining the end, as much of the top group as any other part.
    public func appending(_ id: UUID) -> SplitNode {
        guard case .group(let direction, let children) = self else { return .row(panes + [id]) }
        let joining = SplitChild(node: .pane(id), share: 1 / Double(children.count))
        return Self.tidied(direction, children + [joining]) ?? self
    }

    /// Without `id`, what's left taking up its room; nil if nothing is.
    public func removing(_ id: UUID) -> SplitNode? {
        pruned { $0 != id }
    }

    public func keeping(_ ids: Set<UUID>) -> SplitNode? {
        pruned(keeping: ids.contains)
    }

    private func pruned(keeping isKept: (UUID) -> Bool) -> SplitNode? {
        switch self {
        case .pane(let id):
            return isKept(id) ? self : nil
        case .group(let direction, let children):
            return Self.tidied(direction, children.compactMap { child in
                child.node.pruned(keeping: isKept).map { SplitChild(node: $0, share: child.share) }
            })
        }
    }

    /// A group that's left alone: its shares add up to 1, a part running its
    /// way joins it, and with one part it is that part.
    private static func tidied(_ direction: SplitDirection, _ children: [SplitChild]) -> SplitNode? {
        let total = children.reduce(0) { $0 + $1.share }
        let isSound = total > 0 && total.isFinite && children.allSatisfy { $0.share > 0 }
        let children = children.map { SplitChild(node: $0.node, share: isSound ? $0.share / total : 1 / Double(children.count)) }
        let merged = children.flatMap { child -> [SplitChild] in
            guard case .group(direction, let parts) = child.node else { return [child] }
            return parts.map { SplitChild(node: $0.node, share: $0.share * child.share) }
        }
        return merged.count > 1 ? .group(direction, merged) : merged.first?.node
    }
}

// MARK: - Geometry

extension SplitNode {
    /// The strip between two parts of a group.
    public struct Divider: Sendable, Identifiable {
        /// The child to take at each level, from the top, to reach its group.
        public var path: [Int]
        /// It sits after this child.
        public var index: Int
        public var direction: SplitDirection
        /// The gap it fills.
        public var frame: CGRect
        /// What its group's shares are shares of: its length without gaps.
        public var length: Double

        public var id: [Int] { path + [index] }
    }

    public struct Geometry: Sendable {
        /// How close to the split's outer edge a tab has to be to run along it.
        private static let outerBand = 36.0

        let bounds: CGRect
        public var panes: [UUID: CGRect] = [:]
        public var dividers: [Divider] = []

        /// Where a tab dragged to `point` on `pane`, from its top left, lands:
        /// along the split close to its outer edge, or else on the side of the
        /// pane it's nearest. With one pane there's only that pane's sides.
        public func place(at point: CGPoint, on pane: UUID) -> SplitPlace {
            let frame = panes[pane] ?? bounds
            let x = frame.minX + point.x
            let y = frame.minY + point.y
            let distances = [
                (SplitEdge.left, x - bounds.minX), (.right, bounds.maxX - x),
                (.top, y - bounds.minY), (.bottom, bounds.maxY - y),
            ]
            if !dividers.isEmpty, let nearest = distances.min(by: { $0.1 < $1.1 }), nearest.1 < Self.outerBand {
                return .split(nearest.0)
            }
            return .pane(pane, SplitEdge(x: point.x / frame.width, y: point.y / frame.height))
        }
    }

    public func geometry(in bounds: CGRect, gap: Double) -> Geometry {
        var geometry = Geometry(bounds: bounds)
        lay(in: bounds, gap: gap, path: [], into: &geometry)
        return geometry
    }

    private func lay(in bounds: CGRect, gap: Double, path: [Int], into geometry: inout Geometry) {
        switch self {
        case .pane(let id):
            geometry.panes[id] = bounds
        case .group(let direction, let children):
            let isStacked = direction == .stacked
            let length = (isStacked ? bounds.height : bounds.width) - gap * Double(children.count - 1)
            var start = isStacked ? bounds.minY : bounds.minX
            func slice(_ size: Double) -> CGRect {
                isStacked
                    ? CGRect(x: bounds.minX, y: start, width: bounds.width, height: size)
                    : CGRect(x: start, y: bounds.minY, width: size, height: bounds.height)
            }
            for (index, child) in children.enumerated() {
                let size = max(length * child.share, 0)
                child.node.lay(in: slice(size), gap: gap, path: path + [index], into: &geometry)
                start += size
                if index < children.count - 1 {
                    geometry.dividers.append(Divider(path: path, index: index, direction: direction, frame: slice(gap), length: length))
                    start += gap
                }
            }
        }
    }

    /// With `divider` moved by `distance`, taken from the parts either side of it.
    public func resized(_ divider: Divider, by distance: Double) -> SplitNode {
        changingGroup(at: divider.path[...]) { children in
            let index = divider.index
            guard index + 1 < children.count, divider.length > 0 else { return }
            let pair = children[index].share + children[index + 1].share
            let least = min(Self.minimumShare, pair / 2)
            let first = min(max(children[index].share + distance / divider.length, least), pair - least)
            children[index].share = first
            children[index + 1].share = pair - first
        }
    }

    /// With `divider`'s group evened out; groups inside it keep their own shares.
    public func evened(_ divider: Divider) -> SplitNode {
        changingGroup(at: divider.path[...]) { children in
            for index in children.indices {
                children[index].share = 1 / Double(children.count)
            }
        }
    }

    private func changingGroup(at path: ArraySlice<Int>, _ change: (inout [SplitChild]) -> Void) -> SplitNode {
        guard case .group(let direction, var children) = self else { return self }
        if let index = path.first {
            guard children.indices.contains(index) else { return self }
            children[index].node = children[index].node.changingGroup(at: path.dropFirst(), change)
        } else {
            change(&children)
        }
        return .group(direction, children)
    }
}

// MARK: - In a session

extension SplitNode {
    /// The split a session kept. `layout` counts only if it holds just
    /// `panes`, which it wouldn't if a file was changed behind its back. With
    /// none, as in files from before trees, `panes` are a row of `widths`.
    public static func restored(layout: SplitNode?, panes: [UUID], widths: [Double]) -> SplitNode? {
        var seen = Set<UUID>()
        let panes = panes.filter { seen.insert($0).inserted }
        guard panes.count > 1 else { return nil }
        var placed = Set<UUID>()
        if let layout = layout?.pruned(keeping: { placed.insert($0).inserted }), placed == seen {
            return layout
        }
        return row(panes, shares: widths)
    }
}

extension SplitNode: Codable {
    private enum CodingKeys: String, CodingKey {
        case pane, direction, children
    }

    /// Never fails on what's inside, so a layout from a later build can't lose
    /// the whole session: `restored` falls back on the panes.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let pane = try? container.decode(UUID.self, forKey: .pane) {
            self = .pane(pane)
        } else {
            let direction = (try? container.decode(String.self, forKey: .direction)).flatMap(SplitDirection.init)
            let children = try? container.decode([SplitChild].self, forKey: .children)
            self = .group(direction ?? .sideBySide, children ?? [])
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pane(let id):
            try container.encode(id, forKey: .pane)
        case .group(let direction, let children):
            try container.encode(direction.rawValue, forKey: .direction)
            try container.encode(children, forKey: .children)
        }
    }
}

extension SplitChild: Codable {
    private enum CodingKeys: String, CodingKey {
        case share
    }

    public init(from decoder: Decoder) throws {
        node = try SplitNode(from: decoder)
        share = (try? decoder.container(keyedBy: CodingKeys.self).decode(Double.self, forKey: .share)) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        try node.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(share, forKey: .share)
    }
}
