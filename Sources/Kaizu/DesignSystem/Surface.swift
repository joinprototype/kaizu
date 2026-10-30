import SwiftUI

/// Neutral, opaque surfaces for chrome that floats over web content.
/// Never use materials over pages: the page's colors bleed through.
enum Surface {
    /// Command bar, toasts, popovers.
    static func elevated(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x252428) : .white
    }

    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.1) : .black.opacity(0.08)
    }

    /// Dims the window behind modal chrome.
    static func scrim(_ scheme: ColorScheme) -> Color {
        .black.opacity(scheme == .dark ? 0.4 : 0.18)
    }

    /// Vellum, where Kaizu draws its own pages (Reader's `--paper`).
    static func paper(_ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? 0x1C1A17 : 0xF4EFE3)
    }
}

/// The chart-maker's inks, from the icon's compass rose.
enum Ink {
    static func claret(_ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? 0xD9A08B : 0x8C3A32)
    }

    static func verdigris(_ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? 0x8FB3A0 : 0x3F6B58)
    }
}

/// Translucent fills for controls that sit on a theme backdrop.
enum SidebarFill {
    static func subtle(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.07) : .white.opacity(0.5)
    }

    static func hover(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.06) : .white.opacity(0.35)
    }

    static func selected(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.13) : .white.opacity(0.9)
    }
}
