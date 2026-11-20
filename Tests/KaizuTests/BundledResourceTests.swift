import DesignSystem
import Foundation
@testable import Kaizu
import Testing
@testable import WebEngine

/// A test run has no app bundle, so these come from the repo's Resources
/// folder, the fallback `swift run` uses too. It's found from the source
/// file's own path, which moving the file breaks without failing the build.
struct BundledResourceTests {
    @Test(arguments: [
        ("IMFell-Roman", "ttf", "Fonts"),
        ("IMFell-Italic", "ttf", "Fonts"),
        ("autoconsent-rules", "json", "Scripts"),
        ("readability", "js", "Scripts"),
    ])
    func findsTheRepositorysResources(name: String, ext: String, subdirectory: String) throws {
        let url = try #require(BundledResource.url(named: name, extension: ext, in: subdirectory))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func embedsBothFacesOfTheDisplayFont() {
        #expect(Typeface.webFontFaces.components(separatedBy: "@font-face").count == 3)
    }

    @Test func loadsTheConsentRules() {
        #expect(AutoconsentBridge.rules != nil)
        #expect(AutoconsentBridge.snippets != nil)
    }
}
