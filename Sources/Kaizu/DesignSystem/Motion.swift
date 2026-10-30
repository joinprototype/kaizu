import AppKit
import SwiftUI

/// Named animations, so motion feels consistent and is tuned in one place.
/// Those that move things collapse to no animation when Reduce Motion is
/// on; plain fades (hover) stay, as Apple suggests.
enum Motion {
    /// Chrome reacting to an action: rows, sidebar, overlays closing.
    static var snap: Animation? { reduced(.snappy(duration: 0.22)) }
    /// Something appearing with a little life: command bar, peek, new tabs.
    static var pop: Animation? { reduced(.spring(response: 0.32, dampingFraction: 0.78)) }
    /// Layout moving smoothly: switching spaces, reordering.
    static var glide: Animation? { reduced(.smooth(duration: 0.28)) }
    /// Hover highlights.
    static var hover: Animation? { .easeOut(duration: 0.12) }
    /// A compass needle coming to rest: overshoots a little, twice.
    static var settle: Animation? { reduced(.spring(response: 0.6, dampingFraction: 0.35)) }

    static var isReduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Sidebar rows: new ones grow in from their top edge (sliding would
    /// draw them over the row above), closed ones fade and shrink.
    static var row: AnyTransition { .asymmetric(
        insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity),
        removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .leading))
    ) }

    private static func reduced(_ animation: Animation) -> Animation? {
        isReduced ? nil : animation
    }
}
