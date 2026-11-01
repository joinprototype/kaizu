import AppKit
import CoreText
import SwiftUI

/// Chart art, drawn once into a picture and kept. Live, its paths would be
/// redrawn on every frame anything in the window moves: turning a picture is
/// nothing to the GPU, while a rose and its rhumb lines cost a space switch
/// a third of its frames (measured with KAIZU_DEBUG=tour).
@MainActor
private enum Engraving {
    private static var plates: [String: Image] = [:]

    static func plate(_ key: String, size: CGSize, scheme: ColorScheme, drawing: () -> some View) -> Image? {
        let key = "\(key) \(size) \(scheme)"
        if let plate = plates[key] { return plate }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let renderer = ImageRenderer(content: drawing().frame(width: size.width, height: size.height).environment(\.colorScheme, scheme))
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        // Dragging the sidebar's edge asks for a new size at every step.
        if plates.count > 24 {
            plates.removeAll()
        }
        let plate = Image(decorative: image, scale: scale)
        plates[key] = plate
        return plate
    }
}

/// The rose from Kaizu's icon, with its fleur-de-lis at north: navy cardinal
/// points, gilt half-winds, oxblood quarter-winds. Turn it with `rotationEffect`.
struct CompassRose: View {
    @Environment(\.colorScheme) private var scheme
    let size: CGFloat

    var body: some View {
        Engraving.plate("rose", size: CGSize(width: size, height: size), scheme: scheme) { RoseDrawing() }
            .frame(width: size, height: size)
    }
}

private struct RoseDrawing: View {
    @Environment(\.colorScheme) private var scheme

    private struct Inks {
        var navy, navyLit, gilt, giltLit, red, redLit, outline: Color
    }

    private var inks: Inks {
        scheme == .dark
            ? Inks(
                navy: Color(hex: 0xBDB39A), navyLit: Color(hex: 0xEFE6CF), gilt: Color(hex: 0xB08D3C), giltLit: Color(hex: 0xE2C377),
                red: Color(hex: 0x9E4A56), redLit: Color(hex: 0xD98E98), outline: Color(hex: 0x14161C).opacity(0.6)
            )
            : Inks(
                navy: Color(hex: 0x1C2541), navyLit: Color(hex: 0x3F4F80), gilt: Color(hex: 0x9A7A2E), giltLit: Color(hex: 0xD2AE5F),
                red: Color(hex: 0x7A2335), redLit: Color(hex: 0xA9525F), outline: Color(hex: 0x161C30).opacity(0.55)
            )
    }

    /// U+269C from Apple Symbols, the icon's own, a unit tall and centered.
    private static let fleur: Path = {
        let font = CTFontCreateWithName("Apple Symbols" as CFString, 200, nil)
        var character = Array("\u{269C}".utf16)
        var glyph = [CGGlyph](repeating: 0, count: character.count)
        guard CTFontGetGlyphsForCharacters(font, &character, &glyph, character.count),
              let outline = CTFontCreatePathForGlyph(font, glyph[0], nil)
        else { return Path() }
        let box = outline.boundingBoxOfPath
        // Glyphs are drawn y-up.
        return Path(outline).applying(
            CGAffineTransform(translationX: -box.midX, y: -box.midY).concatenating(CGAffineTransform(scaleX: 1 / box.height, y: -1 / box.height))
        )
    }()

    var body: some View {
        let inks = inks
        Canvas { context, size in
            // Room above north for the fleur.
            let cardinal = min(size.width, size.height) / 2 * 0.82
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            context.translateBy(x: center.x, y: center.y)
            let hairline = max(cardinal / 230, 0.4)

            let ringOuter = cardinal * 0.65
            let ringInner = cardinal * 0.59
            var ring = Path()
            ring.addEllipse(in: CGRect(x: -ringOuter, y: -ringOuter, width: ringOuter * 2, height: ringOuter * 2))
            ring.addEllipse(in: CGRect(x: -ringInner, y: -ringInner, width: ringInner * 2, height: ringInner * 2))
            for tick in 0..<72 {
                let angle = Double(tick) * 5 * .pi / 180
                let inner = tick % 2 == 0 ? ringInner : ringInner + (ringOuter - ringInner) * 0.45
                ring.move(to: CGPoint(x: sin(angle) * inner, y: cos(angle) * inner))
                ring.addLine(to: CGPoint(x: sin(angle) * ringOuter, y: cos(angle) * ringOuter))
            }
            context.stroke(ring, with: .color(inks.navy.opacity(0.85)), lineWidth: hairline * 1.4)

            func point(_ bearing: Double, length: Double, width: Double, lit: Color, shade: Color) {
                var turned = context
                turned.rotate(by: .degrees(bearing))
                for (side, fill) in [(-1.0, lit), (1.0, shade)] {
                    var kite = Path()
                    kite.move(to: .zero)
                    kite.addLine(to: CGPoint(x: side * width, y: -width))
                    kite.addLine(to: CGPoint(x: 0, y: -length))
                    kite.closeSubpath()
                    turned.fill(kite, with: .color(fill))
                    turned.stroke(kite, with: .color(inks.outline), lineWidth: hairline)
                }
            }
            for index in 0..<8 {
                point(22.5 + Double(index) * 45, length: cardinal * 0.48, width: cardinal * 0.07, lit: inks.redLit, shade: inks.red)
            }
            for index in 0..<4 {
                point(45 + Double(index) * 90, length: cardinal * 0.74, width: cardinal * 0.11, lit: inks.giltLit, shade: inks.gilt)
            }
            for index in 0..<4 {
                point(Double(index) * 90, length: cardinal, width: cardinal * 0.17, lit: inks.navyLit, shade: inks.navy)
            }

            let hub = cardinal * 0.095
            let hubBox = CGRect(x: -hub, y: -hub, width: hub * 2, height: hub * 2)
            context.fill(Path(ellipseIn: hubBox), with: .linearGradient(
                Gradient(colors: [inks.giltLit, inks.gilt]),
                startPoint: CGPoint(x: -hub, y: -hub), endPoint: CGPoint(x: hub, y: hub)
            ))
            context.stroke(Path(ellipseIn: hubBox), with: .color(inks.navy), lineWidth: hairline * 1.4)
            let pin = hub * 0.27
            context.fill(Path(ellipseIn: CGRect(x: -pin, y: -pin, width: pin * 2, height: pin * 2)), with: .color(inks.navy))

            var fleur = context
            let height = cardinal * 0.34
            fleur.translateBy(x: 0, y: -(cardinal + height * 0.5))
            fleur.scaleBy(x: height, y: height)
            fleur.fill(Self.fleur, with: .color(inks.giltLit))
        }
    }
}

/// The straight lines sea charts are covered with, running out from one
/// point on all 32 bearings, in the chart-makers' colors: dark for the eight
/// winds, green for the half winds, red for the quarter winds. These stay
/// put: on a real compass it's the card that turns.
struct RhumbWeb: View {
    @Environment(\.colorScheme) private var scheme
    let size: CGSize
    let center: CGPoint
    var strength = 1.0

    var body: some View {
        Engraving.plate("rhumbs \(center) \(strength)", size: size, scheme: scheme) {
            RhumbDrawing(center: center, strength: strength)
        }
        .allowsHitTesting(false)
    }
}

private struct RhumbDrawing: View {
    @Environment(\.colorScheme) private var scheme
    let center: CGPoint
    let strength: Double

    var body: some View {
        let dark = Ink.iron(scheme).opacity(0.13 * strength)
        let green = Ink.verdigris(scheme).opacity(0.16 * strength)
        let red = Ink.claret(scheme).opacity(0.13 * strength)
        Canvas { context, size in
            let reach = hypot(size.width, size.height) * 1.2
            var lines = [Path(), Path(), Path()]
            for index in 0..<32 {
                let angle = Double(index) * 11.25 * .pi / 180
                let group = index % 4 == 0 ? 0 : index % 4 == 2 ? 1 : 2
                lines[group].move(to: center)
                lines[group].addLine(to: CGPoint(x: center.x + sin(angle) * reach, y: center.y + cos(angle) * reach))
            }
            context.stroke(lines[0], with: .color(dark), lineWidth: 0.75)
            context.stroke(lines[1], with: .color(green), lineWidth: 0.5)
            context.stroke(lines[2], with: .color(red), lineWidth: 0.5)
        }
    }
}

/// A chart's border: a firm rule with a fine one just inside it.
struct Neatline: View {
    @Environment(\.colorScheme) private var scheme
    var cornerRadius: CGFloat = 16

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Ink.iron(scheme).opacity(0.42), lineWidth: 1)
            RoundedRectangle(cornerRadius: max(cornerRadius - 3, 0), style: .continuous)
                .strokeBorder(Ink.iron(scheme).opacity(0.2), lineWidth: 0.5)
                .padding(3)
        }
        .allowsHitTesting(false)
    }
}

/// The ticks along a chart's edge that mark degrees and minutes: every
/// tenth one long.
struct Graticule: Shape {
    var spacing: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func ticks(along length: CGFloat, _ tick: (CGFloat, CGFloat) -> Void) {
            var index = 0
            var position = spacing
            while position < length {
                tick(position, index % 10 == 9 ? 10 : index % 5 == 4 ? 7 : 4)
                position += spacing
                index += 1
            }
        }
        ticks(along: rect.width) { x, size in
            path.move(to: CGPoint(x: rect.minX + x, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + x, y: rect.minY + size))
            path.move(to: CGPoint(x: rect.minX + x, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + x, y: rect.maxY - size))
        }
        ticks(along: rect.height) { y, size in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + y))
            path.addLine(to: CGPoint(x: rect.minX + size, y: rect.minY + y))
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY + y))
            path.addLine(to: CGPoint(x: rect.maxX - size, y: rect.minY + y))
        }
        return path
    }
}
