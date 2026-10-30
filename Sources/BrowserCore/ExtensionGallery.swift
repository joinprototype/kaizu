import Foundation

/// The extension stores Kaizu installs from: an extension's page on the
/// Chrome Web Store or Firefox Add-ons, its download, and its archive.
public enum ExtensionGallery {
    public enum Listing: Equatable, Sendable {
        /// The 32-letter extension id.
        case chrome(id: String)
        case firefox(slug: String)

        /// Remembered with the install, to tell a listing's already added.
        public var source: String {
            switch self {
            case .chrome(let id): "chrome:\(id)"
            case .firefox(let slug): "firefox:\(slug)"
            }
        }
    }

    /// The extension a store page is for, if it's an extension's page:
    /// `chromewebstore.google.com/detail/<name>/<id>` (and the old
    /// `chrome.google.com/webstore/detail/…`), or
    /// `addons.mozilla.org/<locale>/firefox/addon/<slug>/`.
    public static func listing(for url: URL?) -> Listing? {
        guard let url, url.scheme == "https", let host = url.host()?.lowercased() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "chromewebstore.google.com", "chrome.google.com":
            let detail = host == "chrome.google.com" ? ["webstore", "detail"] : ["detail"]
            guard path.starts(with: detail), let id = path.dropFirst(detail.count).last(where: isChromeID) else { return nil }
            return .chrome(id: id)
        case "addons.mozilla.org":
            guard let addon = path.firstIndex(of: "addon"), addon > 0, path[addon - 1] == "firefox",
                  let slug = path.dropFirst(addon + 1).first, !slug.isEmpty
            else { return nil }
            return .firefox(slug: slug)
        default:
            return nil
        }
    }

    /// Where the store serves the extension itself (a CRX or an XPI).
    public static func downloadURL(for listing: Listing) -> URL {
        switch listing {
        case .chrome(let id):
            // What Chrome itself asks for (the id is only letters a–p);
            // prodversion only has to be recent enough for the store to
            // serve current extensions.
            return URL(string: "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=141.0"
                + "&acceptformat=crx2,crx3&x=id%3D\(id)%26installsource%3Dondemand%26uc")!
        case .firefox(let slug):
            let escaped = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
            return URL(string: "https://addons.mozilla.org/firefox/downloads/latest/\(escaped)/latest.xpi")!
        }
    }

    public enum ArchiveError: Error {
        case notAnExtension
    }

    /// The ZIP inside a download. A CRX (versions 2 and 3) is a signed
    /// header in front of one; an XPI already is one. The CRX signature
    /// isn't checked: the file comes straight from Google over HTTPS.
    public static func zipArchive(from data: Data) throws -> Data {
        let zipMagic = Data([0x50, 0x4B, 0x03, 0x04])  // "PK\3\4"
        if data.starts(with: zipMagic) { return data }
        guard data.starts(with: Data("Cr24".utf8)), data.count >= 12 else { throw ArchiveError.notAnExtension }
        let version = data.littleEndianUInt32(at: 4)
        let start: Int
        switch version {
        case 2:
            guard data.count >= 16 else { throw ArchiveError.notAnExtension }
            start = 16 + Int(data.littleEndianUInt32(at: 8)) + Int(data.littleEndianUInt32(at: 12))
        case 3:
            start = 12 + Int(data.littleEndianUInt32(at: 8))
        default:
            throw ArchiveError.notAnExtension
        }
        guard start < data.count else { throw ArchiveError.notAnExtension }
        let zip = data.dropFirst(start)
        guard zip.starts(with: zipMagic) else { throw ArchiveError.notAnExtension }
        return Data(zip)
    }

    private static func isChromeID(_ string: String) -> Bool {
        string.count == 32 && string.allSatisfy { ("a"..."p").contains($0) }
    }
}

private extension Data {
    func littleEndianUInt32(at offset: Int) -> UInt32 {
        let start = startIndex + offset
        return self[start..<start + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) }
    }
}
