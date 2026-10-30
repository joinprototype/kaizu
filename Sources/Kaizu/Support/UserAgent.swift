import Foundation

enum UserAgent {
    /// Appended to WebKit's default UA so sites treat us as the installed Safari
    /// (without it, Google and others serve degraded "unsupported browser" pages).
    static let safariSuffix: String = {
        let safari = Bundle(url: URL(fileURLWithPath: "/Applications/Safari.app"))
        let version = safari?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "26.0"
        let parts = version.split(separator: ".")
        let majorMinor = parts.count >= 2 ? "\(parts[0]).\(parts[1])" : "\(version).0"
        return "Version/\(majorMinor) Safari/605.1.15"
    }()
}
