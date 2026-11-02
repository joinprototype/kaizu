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

@Suite struct TimeZoneAnswerTests {
    // Monday 2 Nov 2026, 5 pm in Almaty.
    let now = ISO8601DateFormatter().date(from: "2026-11-02T12:00:00Z")!
    let here = TimeZone(identifier: "Asia/Almaty")!
    let american = Locale(identifier: "en_US")

    func answer(_ text: String, locale: Locale? = nil) -> QuickAnswer? {
        QuickAnswer.evaluate(text, now: now, here: here, locale: locale ?? american)
    }

    @Test(arguments: [
        ("time in tokyo", "9:00 PM", "Time in Tokyo · 4 hours ahead"),
        ("Tokyo time", "9:00 PM", "Time in Tokyo · 4 hours ahead"),
        ("new york time", "7:00 AM", "Time in New York · 10 hours behind"),
        ("what time is it in the uk?", "12:00 PM", "Time in UK · 5 hours behind"),
        ("what's the time in san francisco", "4:00 AM", "Time in San Francisco · 13 hours behind"),
        ("time in mumbai", "5:30 PM", "Time in Mumbai · 0.5 hours ahead"),
        ("time in astana", "5:00 PM", "Time in Astana · same as here"),
        ("time in auckland", "Tue 1:00 AM", "Time in Auckland · 8 hours ahead"),
    ])
    func tellsTheTimeThere(input: String, time: String, question: String) {
        #expect(answer(input)?.answer == time)
        #expect(answer(input)?.question == question)
    }

    @Test(arguments: [
        ("3pm pst in tokyo", "Tue 8:00 AM", "3:00 PM PST in Tokyo"),
        ("3 pm PST to Tokyo", "Tue 8:00 AM", "3:00 PM PST in Tokyo"),
        ("15:30 to london", "10:30 AM", "3:30 PM your time in London"),
        ("3pm in new york", "5:00 AM", "3:00 PM your time in New York"),
        ("noon est", "10:00 PM", "12:00 PM EST in your time"),
        ("midnight in new york", "Sun 2:00 PM", "12:00 AM your time in New York"),
        ("9am sf to nyc", "12:00 PM", "9:00 AM SF in NYC"),
        ("9am london time to tokyo time", "6:00 PM", "9:00 AM London in Tokyo"),
    ])
    func convertsAClockReading(input: String, time: String, question: String) {
        #expect(answer(input)?.answer == time)
        #expect(answer(input)?.question == question)
    }

    @Test func followsTheLocaleClock() {
        #expect(answer("time in tokyo", locale: Locale(identifier: "en_GB"))?.answer == "21:00")
    }

    @Test(arguments: [
        "3 in tokyo", "25:00 to london", "13pm in tokyo", "3:75pm in tokyo", "3pm", "3pm in atlantis", "3pm nowhere to tokyo",
        "time in atlantis", "christmas time", "easter time", "wake time", "cat time", "bed time", "part time", "time",
    ])
    func ignoresEverythingElse(input: String) {
        #expect(answer(input) == nil)
    }

    @Test func nicknamesPointAtRealZones() {
        for identifier in Array(TimeZoneAnswer.knownAs.keys) + Array(TimeZoneAnswer.shorthand.values) {
            #expect(TimeZone(identifier: identifier) != nil, "\(identifier)")
        }
    }
}
