import BrowserCore
import Foundation

/// The page shown when a navigation fails (DNS, offline, TLS…): open water,
/// on the same chart as the rest of Kaizu.
enum ErrorPage {
    static func html(for error: NSError, url: URL?) -> String {
        let host = (url?.displayHost ?? "This page").htmlEscaped
        let message = error.localizedDescription.htmlEscaped
        let retry = url.map { #"<a href="\#($0.absoluteString.htmlEscaped)">Try Again</a>"# } ?? ""
        // The Guide's advice, in large, friendly letters, when the network
        // is the problem (never over a certificate warning).
        let advice = isConnectionProblem(error) ? #"<p class="guide" title="In large, friendly letters">Don’t Panic</p>"# : ""
        let rhumbs = (0..<32).map { index in
            let angle = Double(index) * 11.25 * .pi / 180
            let ink = index % 4 == 0 ? "var(--ink)" : index % 4 == 2 ? "var(--green)" : "var(--accent)"
            return #"<line x2="\#(sin(angle) * 1500)" y2="\#(cos(angle) * 1500)" stroke="\#(ink)"/>"#
        }.joined()
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>Can’t open \(host)</title>
        <style>
          \(Typeface.webFontFaces)
          :root { color-scheme: light dark; --paper: #F4EFE3; --ink: #1C2541; --muted: #6A6456; --accent: #7A2335; --green: #3F6B58; }
          @media (prefers-color-scheme: dark) { :root { --paper: #1C1A17; --ink: #EFE6CF; --muted: #A59A87; --accent: #D9A08B; --green: #8FB3A0; } }
          body { font: 15px/1.5 ui-serif, "New York", Georgia, serif; display: grid; place-items: center; height: 100vh; margin: 0; background: var(--paper); color: var(--muted); overflow: hidden; }
          svg { position: fixed; left: 50%; top: 50%; overflow: visible; opacity: 0.2; stroke-width: 0.6; }
          body::before, body::after { content: ""; position: fixed; pointer-events: none; }
          body::before { inset: 12px; border: 1px solid var(--ink); opacity: 0.4; border-radius: 6px; }
          body::after { inset: 16px; border: 0.5px solid var(--ink); opacity: 0.25; border-radius: 3px; }
          main { position: relative; max-width: 440px; padding: 28px 36px; text-align: center; background: radial-gradient(closest-side, var(--paper) 70%, transparent); }
          h1 { font: 34px/1.15 "Fell", ui-serif, Georgia, serif; color: var(--ink); margin: 0 0 10px; }
          .guide { font: italic 58px/1.1 "Fell", ui-serif, Georgia, serif; color: var(--accent); margin: 0 0 16px; }
          a { display: inline-block; margin-top: 18px; padding: 8px 20px; border-radius: 8px; background: var(--accent); color: var(--paper); text-decoration: none; }
        </style>
        </head>
        <body><svg width="1" height="1" aria-hidden="true">\(rhumbs)</svg><main>\(advice)<h1>Can’t open \(host)</h1><p>\(message)</p>\(retry)</main></body>
        </html>
        """
    }

    private static func isConnectionProblem(_ error: NSError) -> Bool {
        let codes = [
            NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
            NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed,
        ]
        return error.domain == NSURLErrorDomain && codes.contains(error.code)
    }
}
