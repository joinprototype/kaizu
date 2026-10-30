import Foundation
import Testing
@testable import BrowserCore

@Suite struct TrackingParametersTests {
    private func strip(_ string: String) -> String? {
        TrackingParameters.stripped(URL(string: string)!)?.absoluteString
    }

    @Test func removesTrackingButKeepsRealParameters() {
        #expect(strip("https://shop.com/item?id=42&utm_source=news&utm_campaign=fall&fbclid=abc") == "https://shop.com/item?id=42")
    }

    @Test func dropsQueryEntirelyWhenOnlyTracking() {
        #expect(strip("https://example.com/post?gclid=x&utm_medium=cpc#comments") == "https://example.com/post#comments")
    }

    @Test func siteSpecificParametersOnlyApplyOnThatSite() {
        #expect(strip("https://youtu.be/abc123?si=tracking&t=42") == "https://youtu.be/abc123?t=42")
        #expect(strip("https://example.com/?si=1") == nil)
        #expect(strip("https://x.com/user/status/1?s=20&t=abc") == "https://x.com/user/status/1")
    }

    @Test func untouchedURLsReturnNil() {
        #expect(strip("https://example.com/search?q=utm_source") == nil)
        #expect(strip("https://example.com/") == nil)
        #expect(strip("mailto:a@b.com?utm_source=x") == nil)
    }

    @Test func preservesPercentEncoding() {
        #expect(strip("https://example.com/?q=a%26b&utm_source=x") == "https://example.com/?q=a%26b")
    }
}
