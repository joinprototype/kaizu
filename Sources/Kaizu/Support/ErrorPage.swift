import BrowserCore
import Foundation

/// Minimal page shown when a navigation fails (DNS, offline, TLS…).
enum ErrorPage {
    static func html(for error: NSError, url: URL?) -> String {
        let host = (url?.displayHost ?? "This page").htmlEscaped
        let message = error.localizedDescription.htmlEscaped
        let retry = url.map { #"<a href="\#($0.absoluteString.htmlEscaped)">Try Again</a>"# } ?? ""
        // The Guide's advice, in large, friendly letters, when the network
        // is the problem (never over a certificate warning).
        let advice = isConnectionProblem(error) ? #"<p class="guide" title="In large, friendly letters">Don’t Panic</p>"# : ""
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>Can’t open \(host)</title>
        <style>
          :root { color-scheme: light dark; --paper: #F4EFE3; --ink: #2B2620; --muted: #7A6F60; --accent: #6B2E2A; }
          @media (prefers-color-scheme: dark) { :root { --paper: #1C1A17; --ink: #E8E1D3; --muted: #9A8F7E; --accent: #B5574F; } }
          body { font: 14px -apple-system, system-ui; display: grid; place-items: center; height: 100vh; margin: 0; background: var(--paper); color: var(--muted); }
          main { max-width: 420px; text-align: center; }
          h1 { font: 600 24px ui-serif, Georgia, serif; color: var(--ink); margin: 0 0 8px; }
          .guide { font: 600 30px ui-rounded, -apple-system, system-ui; letter-spacing: 0.04em; color: var(--accent); margin: 0 0 14px; }
          a { display: inline-block; margin-top: 16px; padding: 7px 16px; border-radius: 8px; background: var(--accent); color: #F4EFE3; text-decoration: none; }
        </style>
        </head>
        <body><main>\(advice)<h1>Can’t open \(host)</h1><p>\(message)</p>\(retry)</main></body>
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
