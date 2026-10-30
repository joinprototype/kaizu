import AppKit

/// Favicons cached in memory and on disk, keyed by host, so pinned and restored
/// tabs show icons without loading their pages.
@MainActor
final class FaviconStore {
    static let shared = FaviconStore()

    /// Picks the best icon link on the page; prefers sized PNG/ICO icons over
    /// apple-touch-icons, and SVG last (NSImage support for SVG is spotty).
    static let discoveryScript = """
    (() => {
      const links = Array.from(document.querySelectorAll('link[rel~="icon"], link[rel="apple-touch-icon"], link[rel="apple-touch-icon-precomposed"]'));
      const score = (link) => {
        const rel = (link.getAttribute('rel') || '').toLowerCase();
        if (/\\.svg($|\\?)/i.test(link.href) || link.type === 'image/svg+xml') return 1;
        if (rel.includes('apple-touch-icon')) return 20;
        const size = parseInt((link.getAttribute('sizes') || '').split('x')[0], 10);
        return isNaN(size) ? 32 : Math.min(size, 256) + 1;
      };
      links.sort((a, b) => score(b) - score(a));
      return links.length ? links[0].href : '';
    })()
    """

    private static let maxBytes = 1 << 20

    private var memory: [String: NSImage] = [:]
    /// Hosts with no icon on disk, so lists (History) don't re-check per render.
    private var misses: Set<String> = []
    private let directory: URL
    private let session = URLSession(configuration: .ephemeral)

    private init() {
        directory = AppPaths.support.appending(path: "Favicons", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func cachedImage(for host: String) -> NSImage? {
        if let image = memory[host] { return image }
        guard !misses.contains(host) else { return nil }
        guard let data = try? Data(contentsOf: file(for: host)), let image = NSImage(data: data) else {
            misses.insert(host)
            return nil
        }
        memory[host] = image
        return image
    }

    /// `remember: false` (private windows) keeps the icon out of the disk cache.
    /// The page chooses the URL, so only web URLs and small files are fetched.
    func fetch(_ url: URL, host: String, remember: Bool = true) async -> NSImage? {
        guard ["http", "https"].contains(url.scheme?.lowercased()),
              let (bytes, response) = try? await session.bytes(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              response.expectedContentLength <= Self.maxBytes
        else { return nil }
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > Self.maxBytes { return nil }
            }
        } catch {
            return nil
        }
        guard let image = NSImage(data: data), image.isValid else { return nil }
        guard remember else { return image }
        memory[host] = image
        misses.remove(host)
        try? data.write(to: file(for: host), options: .atomic)
        return image
    }

    private func file(for host: String) -> URL {
        let safe = host.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        return directory.appending(path: safe)
    }
}
