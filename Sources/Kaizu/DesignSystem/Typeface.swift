import AppKit
import CoreText
import SwiftUI

/// Kaizu's two voices, the same as its website's. IM Fell, cut in the 1670s,
/// for names and headings: what a chart-maker would have lettered. Everything
/// read small is New York, the system serif, set at the root of each window
/// with `fontDesign(.serif)`.
enum Typeface {
    private static let roman = "IM_FELL_Double_Pica_Roman"
    private static let italic = "IM_FELL_Double_Pica_Italic"

    /// Once, before the first window.
    static func register() {
        for name in ["IMFell-Roman", "IMFell-Italic"] {
            guard let url = BundledResource.url(named: name, extension: "ttf", in: "Fonts") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Land on a chart is lettered upright: names of things.
    static func display(_ size: CGFloat) -> Font {
        .custom(roman, fixedSize: size)
    }

    /// Water is lettered in italics: sections, and what's said in passing.
    static func water(_ size: CGFloat) -> Font {
        .custom(italic, fixedSize: size)
    }

    static func displayField(_ size: CGFloat) -> NSFont {
        NSFont(name: roman, size: size) ?? .systemFont(ofSize: size)
    }

    /// IM Fell for web pages Kaizu writes itself (Reader, the error page):
    /// they run in another process, which can't see the app's fonts. Embedded,
    /// because Reader's security policy lets nothing else load.
    static let webFontFaces: String = [("normal", "IMFell-Roman"), ("italic", "IMFell-Italic")].compactMap { style, name in
        guard let url = BundledResource.url(named: name, extension: "ttf", in: "Fonts"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return #"@font-face { font-family: "Fell"; font-style: \#(style); src: url(data:font/ttf;base64,\#(data.base64EncodedString())); }"#
    }.joined(separator: "\n")

    /// New York, for AppKit fields.
    static func textField(_ size: CGFloat) -> NSFont {
        let system = NSFont.systemFont(ofSize: size)
        return system.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? system
    }
}
