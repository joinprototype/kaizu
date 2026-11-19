import AppKit
import SwiftUI

/// Named animations, so motion feels consistent and is tuned in one place.
/// With Reduce Motion on, what would slide or scale dissolves instead (see
/// `dissolving`), as Apple suggests, and layout simply changes.
public enum Motion {
    /// Chrome reacting to an action: rows, sidebar, overlays closing.
    public static var snap: Animation? { isReduced ? dissolve : .snappy(duration: 0.22) }
    /// Something appearing with a little life: command bar, peek, new tabs.
    public static var pop: Animation? { isReduced ? dissolve : .spring(response: 0.32, dampingFraction: 0.78) }
    /// Layout moving smoothly: switching spaces, reordering.
    public static var glide: Animation? { reduced(.smooth(duration: 0.28)) }
    /// Hover highlights.
    public static var hover: Animation? { .easeOut(duration: 0.12) }
    /// A compass needle coming to rest: overshoots a little, twice.
    public static var settle: Animation? { reduced(.spring(response: 0.6, dampingFraction: 0.35)) }

    public static var isReduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Sidebar rows: new ones grow in from their top edge (sliding would
    /// draw them over the row above), closed ones fade and shrink.
    public static var row: AnyTransition { dissolving(.asymmetric(
        insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity),
        removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .leading))
    )) }

    /// A transition that moves or scales, for what comes and goes.
    public static func dissolving(_ transition: AnyTransition) -> AnyTransition {
        isReduced ? .opacity : transition
    }

    private static let dissolve = Animation.easeOut(duration: 0.15)

    private static func reduced(_ animation: Animation) -> Animation? {
        isReduced ? nil : animation
    }
}
