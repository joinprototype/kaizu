import BrowserCore
import Foundation
import Testing

struct ExtensionGalleryTests {
    private let uBlockLite = "ddkjiahejlhfcafbddmgiahcphecmpfh"

    @Test func findsChromeWebStoreListings() {
        let listing = ExtensionGallery.Listing.chrome(id: uBlockLite)
        #expect(ExtensionGallery.listing(for: URL(string: "https://chromewebstore.google.com/detail/ublock-origin-lite/\(uBlockLite)")) == listing)
        #expect(ExtensionGallery.listing(for: URL(string: "https://chromewebstore.google.com/detail/\(uBlockLite)?hl=en")) == listing)
        #expect(ExtensionGallery.listing(for: URL(string: "https://chromewebstore.google.com/detail/ublock-origin-lite/\(uBlockLite)/reviews")) == listing)
        #expect(ExtensionGallery.listing(for: URL(string: "https://chrome.google.com/webstore/detail/ublock-origin-lite/\(uBlockLite)")) == listing)
    }

    @Test func findsFirefoxListings() {
        #expect(ExtensionGallery.listing(for: URL(string: "https://addons.mozilla.org/en-US/firefox/addon/darkreader/")) == .firefox(slug: "darkreader"))
        #expect(ExtensionGallery.listing(for: URL(string: "https://addons.mozilla.org/firefox/addon/darkreader")) == .firefox(slug: "darkreader"))
    }

    @Test func ignoresOtherPages() {
        for page in [
            "https://chromewebstore.google.com/",
            "https://chromewebstore.google.com/category/extensions",
            "https://chromewebstore.google.com/detail/not-an-id",
            "http://chromewebstore.google.com/detail/x/\(uBlockLite)",
            "https://example.com/detail/x/\(uBlockLite)",
            "https://addons.mozilla.org/en-US/firefox/",
            "https://addons.mozilla.org/en-US/android/addon/darkreader/",
        ] {
            #expect(ExtensionGallery.listing(for: URL(string: page)) == nil, "\(page)")
        }
    }

    @Test func downloadsFromTheStores() {
        let chrome = ExtensionGallery.downloadURL(for: .chrome(id: uBlockLite)).absoluteString
        #expect(chrome.hasPrefix("https://clients2.google.com/service/update2/crx?"))
        #expect(chrome.contains("x=id%3D\(uBlockLite)%26installsource%3Dondemand%26uc"))
        #expect(ExtensionGallery.downloadURL(for: .firefox(slug: "darkreader")).absoluteString
            == "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi")
    }

    @Test func unwrapsTheZipInACRX() throws {
        let zip = Data([0x50, 0x4B, 0x03, 0x04, 1, 2, 3])
        let header = Data(repeating: 0xAB, count: 5)
        let crx3 = Data("Cr24".utf8) + uint32(3) + uint32(5) + header + zip
        #expect(try ExtensionGallery.zipArchive(from: crx3) == zip)
        let crx2 = Data("Cr24".utf8) + uint32(2) + uint32(2) + uint32(3) + header + zip
        #expect(try ExtensionGallery.zipArchive(from: crx2) == zip)
        #expect(try ExtensionGallery.zipArchive(from: zip) == zip)
    }

    @Test func rejectsWhatIsntAnExtension() {
        #expect(throws: ExtensionGallery.ArchiveError.self) { try ExtensionGallery.zipArchive(from: Data("<html>".utf8)) }
        #expect(throws: ExtensionGallery.ArchiveError.self) {
            try ExtensionGallery.zipArchive(from: Data("Cr24".utf8) + uint32(3) + uint32(999) + Data([1, 2]))
        }
    }

    private func uint32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
