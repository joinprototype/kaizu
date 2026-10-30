import SwiftUI

/// May 25 is Towel Day, for Douglas Adams: "A towel is about the most
/// massively useful thing an interstellar hitchhiker can have." On that
/// day a towel hangs in the sidebar.
enum TowelDay {
    static var isToday: Bool {
        #if DEBUG
        // KAIZU_TOWEL=1 hangs it on any day, for screenshots.
        if ProcessInfo.processInfo.environment["KAIZU_TOWEL"] == "1" { return true }
        #endif
        let today = Calendar.current.dateComponents([.month, .day], from: .now)
        return today.month == 5 && today.day == 25
    }
}

struct TowelButton: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @State private var isHovering = false

    var body: some View {
        Button {
            store.showToast("Happy Towel Day. You know where your towel is.")
        } label: {
            Towel()
                .frame(width: 13, height: 15)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHovering ? SidebarFill.hover(scheme) : .clear)
                        .animation(Motion.hover, value: isHovering)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHoverFade($isHovering)
        .help("Towel Day, for Douglas Adams")
    }
}

/// A towel over a rail: the fold, two claret stripes and a fringe.
private struct Towel: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, size in
            let width = size.width, height = size.height
            let line = 1.2
            func stroke(from start: CGPoint, to end: CGPoint, with shading: GraphicsContext.Shading = .foreground, width lineWidth: CGFloat = line) {
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(path, with: shading, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
            // The rail, with a knob at each end.
            stroke(from: CGPoint(x: width * 0.08, y: height * 0.14), to: CGPoint(x: width * 0.92, y: height * 0.14))
            for x in [0.06, 0.94] {
                context.fill(Path(ellipseIn: CGRect(x: width * x - 1.2, y: height * 0.14 - 1.2, width: 2.4, height: 2.4)), with: .foreground)
            }
            let cloth = CGRect(x: width * 0.22, y: height * 0.14, width: width * 0.56, height: height * 0.7)
            context.stroke(Path(roundedRect: cloth, cornerRadius: 1), with: .foreground, lineWidth: line)
            stroke(from: CGPoint(x: cloth.minX, y: height * 0.42), to: CGPoint(x: cloth.maxX, y: height * 0.42))
            for y in [0.6, 0.7] {
                stroke(from: CGPoint(x: cloth.minX, y: height * y), to: CGPoint(x: cloth.maxX, y: height * y), with: .color(Ink.claret(scheme)))
            }
            for i in 0..<4 {
                let x = cloth.minX + cloth.width * (0.14 + Double(i) * 0.24)
                stroke(from: CGPoint(x: x, y: cloth.maxY), to: CGPoint(x: x, y: height * 0.96), width: 0.9)
            }
        }
    }
}
