import Foundation
import Testing
@testable import BrowserCore

@Suite struct QuickAnswerTests {
    @Test(arguments: [
        ("20+20", "40"),
        ("20 + 20", "40"),
        ("(3+4)*2^3", "56"),
        ("2^3^2", "512"),
        ("10/4", "2.5"),
        ("-5 + 2", "-3"),
        ("15% of 80", "12"),
        ("1,000 * 3", "3000"),
        ("6 × 7", "42"),
        ("sqrt(16) + 1", "5"),
        ("2*pi", "6.2831853072"),
        ("0.1+0.2", "0.3"),
        ("-2^2", "-4"),
        ("2^-1", "0.5"),
        ("10-3", "7"),
    ])
    func calculates(input: String, expected: String) {
        #expect(QuickAnswer.evaluate(input)?.answer == expected)
    }

    @Test(arguments: [
        "the answer to life, the universe and everything",
        "Answer to the Ultimate Question of Life, the Universe, and Everything?",
        "life the universe and everything",
    ])
    func knowsTheAnswer(input: String) {
        #expect(QuickAnswer.evaluate(input)?.answer == "42")
    }

    @Test(arguments: ["2026", "covid-19", "hello world", "1/0", "github.com", "v1.2", "(", "3 +", "swift 6", "-7", "2026-10-25", "555-1234", "07-11"])
    func ignoresNonMath(input: String) {
        #expect(QuickAnswer.evaluate(input) == nil)
    }

    @Test(arguments: [
        ("10 km to mi", "6.21 mi"),
        ("100 f in c", "37.78 c"),
        ("5 kg to lb", "11.02 lb"),
        ("2 gb to mb", "2000 mb"),
        ("90 min in h", "1.5 h"),
    ])
    func converts(input: String, expected: String) {
        #expect(QuickAnswer.evaluate(input)?.answer == expected)
    }

    @Test(arguments: ["10 km to kg", "5 apples to oranges", "km to mi"])
    func ignoresImpossibleConversions(input: String) {
        #expect(QuickAnswer.evaluate(input) == nil)
    }
}

@Suite struct SearchShortcutTests {
    @Test func matchesKeywordAndQuery() throws {
        let match = try #require(SearchShortcut.match("yt lofi beats"))
        #expect(match.shortcut.name == "YouTube")
        #expect(match.shortcut.url(for: match.query)?.absoluteString == "https://www.youtube.com/results?search_query=lofi%20beats")
    }

    @Test func toleratesHandTypedShortcuts() throws {
        let shortcut = SearchShortcut(keyword: " wiki ", name: "Wiki", template: "wiki.example.com/search?q=%s")
        let match = try #require(SearchShortcut.match("wiki tides", in: [shortcut]))
        #expect(match.shortcut.url(for: match.query)?.absoluteString == "https://wiki.example.com/search?q=tides")
    }

    @Test(arguments: ["yt", "yt  ", "youtube cats", "ytcats"])
    func ignoresNonShortcuts(input: String) {
        #expect(SearchShortcut.match(input) == nil)
    }
}

@Suite struct CurrencyConversionTests {
    let rates = CurrencyRates(perEuro: ["USD": 1.25, "GBP": 0.8, "JPY": 160, "KZT": 500], date: "2026-10-23")

    @Test(arguments: [
        ("100 usd to eur", "80 EUR"),
        ("$20 in £", "12.8 GBP"),
        ("50 euros in yen", "8000 JPY"),
        ("1,000 GBP to usd", "1562.5 USD"),
        ("1,5 eur to usd", "1.88 USD"),
        ("1.000,50 eur to usd", "1250.63 USD"),
        ("100 usd to kzt", "40000 KZT"),
        ("₸5000 in usd", "12.5 USD"),
        ("100 euros in tenge", "50000 KZT"),
    ])
    func converts(input: String, answer: String) {
        #expect(QuickAnswer.evaluate(input, rates: rates)?.answer == answer)
    }

    @Test func citesTheRateDate() {
        #expect(QuickAnswer.evaluate("100 usd to eur", rates: rates)?.question == "100 USD in EUR · Frankfurter 2026-10-23")
    }

    @Test(arguments: ["100 usd to usd", "$20 usd in eur", "usd to eur", "100 abc to eur", "100 usd"])
    func ignoresNonConversions(input: String) {
        #expect(CurrencyConversion.parse(input) == nil)
    }

    @Test func waitsForRates() {
        #expect(CurrencyConversion.parse("100 usd to eur") != nil)
        #expect(QuickAnswer.evaluate("100 usd to eur") == nil)
    }

    @Test func staysQuietWithoutARate() {
        #expect(CurrencyConversion.parse("100 usd to pen") != nil)
        #expect(QuickAnswer.evaluate("100 usd to pen", rates: rates) == nil)
    }

    @Test func parsesFrankfurterRates() throws {
        let json = """
        [{"date":"2026-10-23","base":"EUR","quote":"KZT","rate":506.98},
         {"date":"2026-10-24","base":"EUR","quote":"USD","rate":1.1177},
         {"date":"2026-10-22","base":"EUR","quote":"XXX","rate":0}]
        """
        let parsed = try #require(CurrencyRates(frankfurterJSON: Data(json.utf8)))
        #expect(parsed.perEuro["KZT"] == 506.98)
        #expect(parsed.perEuro["EUR"] == 1)
        #expect(parsed.perEuro["XXX"] == nil)
        #expect(parsed.date == "2026-10-24")
        #expect(CurrencyRates(frankfurterJSON: Data("<html>Sign in to Wi-Fi</html>".utf8)) == nil)
        #expect(CurrencyRates(frankfurterJSON: Data("[]".utf8)) == nil)
    }
}
