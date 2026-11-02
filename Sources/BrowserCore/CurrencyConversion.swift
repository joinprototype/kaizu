import Foundation

/// Rates against the euro from Frankfurter (https://frankfurter.dev), which
/// gathers what central banks publish. The ECB alone covers about 30 currencies.
public struct CurrencyRates: Equatable, Sendable {
    /// Units of each currency per euro, including EUR itself.
    public var perEuro: [String: Double]
    /// The newest day among the rates, as published ("2026-10-23"). Banks
    /// publish on different days, so some rates can be a few days older.
    public var date: String?

    public init(perEuro: [String: Double], date: String? = nil) {
        self.perEuro = perEuro.merging(["EUR": 1]) { current, _ in current }
        self.date = date
    }

    /// Parses Frankfurter's list of rates; nil for anything else (an error
    /// page, a portal).
    public init?(frankfurterJSON data: Data) {
        struct Row: Decodable {
            let date: String
            let quote: String
            let rate: Double
        }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return nil }
        let rates = Dictionary(rows.filter { $0.rate > 0 }.map { ($0.quote, $0.rate) }) { current, _ in current }
        guard rates["USD"] != nil else { return nil }
        self.init(perEuro: rates, date: rows.map(\.date).max())
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

    /// Any ISO currency, so a conversion is recognised before rates arrive.
    /// One the rates turn out not to cover gets no answer.
    static let codes = Set(Locale.commonISOCurrencyCodes)
    static let aliases: [String: String] = [
        "$": "USD", "dollar": "USD", "dollars": "USD", "€": "EUR", "euro": "EUR", "euros": "EUR",
        "£": "GBP", "pound": "GBP", "pounds": "GBP", "¥": "JPY", "yen": "JPY", "₹": "INR", "₩": "KRW",
        "fr": "CHF", "francs": "CHF", "yuan": "CNY", "rmb": "CNY", "₸": "KZT", "tenge": "KZT",
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
        let source = rates.date.map { " · Frankfurter \($0)" } ?? ""
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
