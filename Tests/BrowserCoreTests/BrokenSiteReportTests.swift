import Foundation
import Testing
@testable import BrowserCore

@Suite struct BrokenSiteReportTests {
    private let page = URL(string: "https://user:secret@shop.example.com/orders/1234?token=abc&utm_source=news#receipt")!

    @Test func keepsThePageAddressOutByDefault() {
        let text = BrokenSiteReport(url: page, problem: .looksWrong).text
        #expect(text.contains("Site: shop.example.com\n"))
        for word in ["orders", "1234", "token", "abc", "receipt", "user", "secret"] {
            #expect(!text.contains(word))
        }
    }

    @Test func addsTheAddressWhenAskedWithoutLoginOrTracking() {
        let text = BrokenSiteReport(url: page, problem: .looksWrong, includesAddress: true).text
        #expect(text.contains("Address: https://shop.example.com/orders/1234?token=abc#receipt\n"))
        #expect(!text.contains("secret"))
        #expect(!text.contains("utm_source"))
    }

    @Test func onlyWebsitesHaveASite() {
        #expect(BrokenSiteReport.site(of: URL(string: "https://WWW.Example.com/a")!) == "www.example.com")
        #expect(BrokenSiteReport.site(of: URL(string: "http://localhost:8080/")!) == "localhost")
        #expect(BrokenSiteReport.site(of: URL(string: "about:blank")!) == nil)
        #expect(BrokenSiteReport.site(of: URL(fileURLWithPath: "/tmp/page.html")) == nil)
        #expect(BrokenSiteReport.site(of: URL(string: "ftp://example.com/")!) == nil)
    }

    @Test func textCarriesTheAnswersThenTheDetails() {
        let report = BrokenSiteReport(
            url: URL(string: "https://example.com/")!,
            problem: .media,
            note: "  Stops after a second.\n",
            blockingTest: .fixed,
            details: ["Kaizu 0.1.3 (4)", "Extensions: none"]
        )
        #expect(report.subject == "Kaizu broken site: example.com")
        #expect(report.text == """
        Site: example.com
        Problem: Video or sound won't play
        Fixed by turning blocking off: Yes

        Stops after a second.

        ---
        Kaizu 0.1.3 (4)
        Extensions: none

        """)
    }

    @Test func blankNoteLeavesNoGap() {
        let report = BrokenSiteReport(url: URL(string: "https://example.com/")!, problem: .other, note: " \n ")
        #expect(report.text == """
        Site: example.com
        Problem: Something else
        Fixed by turning blocking off: Not tried

        ---

        """)
    }
}
