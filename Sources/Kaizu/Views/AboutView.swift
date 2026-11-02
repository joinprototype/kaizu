import SwiftUI

/// Kaizu ▸ About Kaizu: the chart's title block, with the credits a chart
/// would carry.
struct AboutView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Surface.paper(scheme)
            VStack(spacing: 8) {
                CompassRose(size: 132)
                    .padding(.bottom, 4)
                Text("Kaizu")
                    .font(Typeface.display(50))
                    .foregroundStyle(Ink.iron(scheme))
                // 海図, "sea chart".
                Text("海図")
                    .font(.system(size: 14))
                    .tracking(5)
                    .foregroundStyle(Ink.claret(scheme))
                Text("Version \(Diagnostics.appVersion)")
                    .font(Typeface.water(15))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                Text("Made with love.")
                    .font(Typeface.water(19))
                    .foregroundStyle(Ink.iron(scheme))
                    .padding(.top, 10)
                Text("Pages by WebKit. Type by Igino Marini, after the Fell types of 1672. Blocking lists by the EasyList authors, cookie pop-ups by DuckDuckGo's autoconsent, Reader by Mozilla's Readability.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 44)
        }
        .overlay { ChartFrame(cornerRadius: 5, inset: 10) }
        .frame(width: 380, height: 470)
    }
}
