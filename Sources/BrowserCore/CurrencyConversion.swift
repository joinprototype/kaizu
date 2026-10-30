import Foundation

/// Euro reference rates from the European Central Bank's daily feed
/// (https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml).
public struct CurrencyRates: Equatable, Sendable {
    /// Units of each currency per euro, including EUR itself.
    public var perEuro: [String: Double]
    /// The day the rates are for, as published ("2026-10-23").
    public var date: String?

    public init(perEuro: [String: Double], date: String? = nil) {
        self.perEuro = perEuro.merging(["EUR": 1]) { current, _ in current }
        self.date = date
    }

    /// Parses the ECB XML; nil for anything else (an error page, a portal).
    public init?(ecbXML data: Data) {
        guard let xml = String(data: data, encoding: .utf8) else { return nil }
        var rates: [String: Double] = [:]
        for match in xml.matches(of: /currency=['"]([A-Z]{3})['"]\s+rate=['"]([\d.]+)['"]/) {
            if let rate = Double(match.2), rate > 0 {
                rates[String(match.1)] = rate
            }
        }
        guard rates["USD"] != nil else { return nil }
        self.init(perEuro: rates, date: xml.firstMatch(of: /time=['"](\d{4}-\d{2}-\d{2})['"]/).map { String($0.1) })
    }

    public func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let fromRate = perEuro[from], let toRate = perEuro[to] else { return nil }
        return amount / fromRate * toRate
    }
}

/// "100 usd to eur", "$20 in £", "50 euros in yen".
public enum CurrencyConversion {
    public struct Request: Equatable, Sendable {
        public var amount: Double
        public var from: String
        public var to: String
    }

    /// Currencies the ECB publishes, plus the euro.
    static let codes: Set<String> = [
        "EUR", "USD", "JPY", "BGN", "CZK", "DKK", "GBP", "HUF", "PLN", "RON", "SEK", "CHF", "ISK", "NOK",
        "TRY", "AUD", "BRL", "CAD", "CNY", "HKD", "IDR", "ILS", "INR", "KRW", "MXN", "MYR", "NZD", "PHP",
        "SGD", "THB", "ZAR",
    ]
    static let aliases: [String: String] = [
        "$": "USD", "dollar": "USD", "dollars": "USD", "€": "EUR", "euro": "EUR", "euros": "EUR",
        "£": "GBP", "pound": "GBP", "pounds": "GBP", "¥": "JPY", "yen": "JPY", "₹": "INR", "₩": "KRW",
        "fr": "CHF", "francs": "CHF", "yuan": "CNY", "rmb": "CNY",
    ]

    /// Recognises a conversion without needing rates, so callers can fetch
    /// them only once someone actually asks.
    public static func parse(_ text: String) -> Request? {
        let pattern = /^\s*([^\s\d.,-]*)\s*([\d][\d.,]*)\s*([^\s\d]*)\s+(?:to|in|as)\s+([^\s\d]+)\s*$/
        guard let match = text.lowercased().wholeMatch(of: pattern),
              let amount = amount(String(match.2)),
              match.1.isEmpty != match.3.isEmpty,
              let from = currency(String(match.1.isEmpty ? match.3 : match.1)),
              let to = currency(String(match.4)), from != to
        else { return nil }
        return Request(amount: amount, from: from, to: to)
    }

    static func convert(_ text: String, rates: CurrencyRates) -> QuickAnswer? {
        guard let request = parse(text),
              let value = rates.convert(request.amount, from: request.from, to: request.to)
        else { return nil }
        let source = rates.date.map { " · ECB \($0)" } ?? ""
        return QuickAnswer(
            question: "\(QuickAnswer.format(request.amount)) \(request.from) in \(request.to)\(source)",
            answer: "\(QuickAnswer.format((value * 100).rounded() / 100)) \(request.to)"
        )
    }

    /// "1,000.50" and "1.000,50" are both a thousand; "1,5" is one and a half.
    private static func amount(_ text: String) -> Double? {
        let lastComma = text.lastIndex(of: ","), lastDot = text.lastIndex(of: ".")
        let decimalComma = lastComma.map { comma in
            lastDot.map { comma > $0 } ?? (text.distance(from: comma, to: text.endIndex) <= 3)
        } ?? false
        let normalized = decimalComma
            ? text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            : text.replacingOccurrences(of: ",", with: "")
        return Double(normalized)
    }

    private static func currency(_ word: String) -> String? {
        if let alias = aliases[word] { return alias }
        let code = word.uppercased()
        return codes.contains(code) ? code : nil
    }
}
