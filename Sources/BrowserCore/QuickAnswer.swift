import Foundation

/// An instant answer for the command bar: arithmetic, a unit conversion or
/// a currency conversion, like Spotlight and Raycast. Computed locally; the
/// only network use is fetching public exchange rates.
public struct QuickAnswer: Equatable, Sendable {
    /// What was understood, e.g. "20 + 20" or "10 km in miles".
    public var question: String
    /// The result, ready to copy, e.g. "40" or "6.21 mi".
    public var answer: String

    /// Tries the calculator, then units, then currencies (when rates are known).
    public static func evaluate(_ text: String, rates: CurrencyRates? = nil) -> QuickAnswer? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        if let answer = deepThought(input) { return answer }
        if let value = Calculator.evaluate(input) {
            return QuickAnswer(question: input, answer: format(value))
        }
        return UnitConversion.convert(input) ?? rates.flatMap { CurrencyConversion.convert(input, rates: $0) }
    }

    /// Seven and a half million years of computation, cached.
    private static func deepThought(_ input: String) -> QuickAnswer? {
        let words = input.lowercased().split { !$0.isLetter }.joined(separator: " ")
        guard words.hasSuffix("life the universe and everything") else { return nil }
        return QuickAnswer(question: "Life, the Universe and Everything", answer: "42")
    }

    static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if value != 0, abs(value) >= 1e15 || abs(value) < 1e-6 {
            formatter.numberStyle = .scientific
            formatter.maximumSignificantDigits = 8
        } else {
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = false
            formatter.maximumFractionDigits = 10
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

// MARK: - Calculator

/// A small recursive-descent evaluator: + − × ÷ ^ %, parentheses, a few
/// functions and constants. Only answers inputs that are clearly math
/// (an operator or function is required, so "2026" or "covid-19" don't count).
enum Calculator {
    private static let functions: [String: @Sendable (Double) -> Double] = [
        "sqrt": { $0.squareRoot() }, "abs": { Swift.abs($0) }, "round": { $0.rounded() },
        "floor": { $0.rounded(.down) }, "ceil": { $0.rounded(.up) },
        "ln": { Foundation.log($0) }, "log": { Foundation.log10($0) },
        "sin": { Foundation.sin($0) }, "cos": { Foundation.cos($0) }, "tan": { Foundation.tan($0) },
    ]
    private static let constants: [String: Double] = ["pi": .pi, "π": .pi, "e": M_E]

    static func evaluate(_ text: String) -> Double? {
        guard !looksLikeCode(text) else { return nil }
        let normalized = text.lowercased()
            .replacingOccurrences(of: " of ", with: " * ")  // "15% of 80"
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: ",", with: "")
        guard let tokens = tokenize(normalized), isMath(tokens) else { return nil }
        var parser = Parser(tokens: tokens)
        guard let value = parser.parseExpression(), parser.isAtEnd, value.isFinite else { return nil }
        return value
    }

    enum Token: Equatable {
        case number(Double)
        case name(String)
        case symbol(Character)
    }

    private static func tokenize(_ text: String) -> [Token]? {
        var tokens: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character.isWhitespace {
                index = text.index(after: index)
            } else if character.isNumber || character == "." {
                let start = index
                while index < text.endIndex, text[index].isNumber || text[index] == "." {
                    index = text.index(after: index)
                }
                guard let value = Double(text[start..<index]) else { return nil }
                tokens.append(.number(value))
            } else if character.isLetter {
                let start = index
                while index < text.endIndex, text[index].isLetter {
                    index = text.index(after: index)
                }
                let name = String(text[start..<index])
                guard functions[name] != nil || constants[name] != nil else { return nil }
                tokens.append(.name(name))
            } else if "+-*/^%()".contains(character) {
                tokens.append(.symbol(character))
                index = text.index(after: index)
            } else {
                return nil
            }
        }
        return tokens
    }

    /// Digits joined by hyphens, without spaces, are a date, a phone number
    /// or a code (2026-10-25, 555-1234), not a subtraction; short ones like
    /// 10-3 still count.
    private static func looksLikeCode(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count > 1, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return false }
        return parts.count > 2 || parts.contains { $0.count > 1 && $0.first == "0" } || parts.joined().count >= 7
    }

    /// Requires an actual operation, so a lone number isn't "calculated".
    private static func isMath(_ tokens: [Token]) -> Bool {
        let hasOperation = tokens.contains { token in
            switch token {
            case .symbol(let symbol): "+*/^%".contains(symbol) || (symbol == "-" && tokens.count > 2)
            case .name(let name): functions[name] != nil
            case .number: false
            }
        }
        return hasOperation && tokens.contains { if case .number = $0 { true } else { false } }
    }

    private struct Parser {
        let tokens: [Token]
        var position = 0

        var isAtEnd: Bool { position == tokens.count }

        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let symbol = peekSymbol(in: "+-") {
                position += 1
                guard let rhs = parseTerm() else { return nil }
                value = symbol == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func parseTerm() -> Double? {
            guard var value = parseUnary() else { return nil }
            while let symbol = peekSymbol(in: "*/") {
                position += 1
                guard let rhs = parseUnary() else { return nil }
                value = symbol == "*" ? value * rhs : value / rhs
            }
            return value
        }

        /// Signs bind looser than ^, as in math: -2^2 is -4.
        mutating func parseUnary() -> Double? {
            if peekSymbol(in: "-") != nil {
                position += 1
                return parseUnary().map { -$0 }
            }
            if peekSymbol(in: "+") != nil {
                position += 1
                return parseUnary()
            }
            return parsePower()
        }

        mutating func parsePower() -> Double? {
            guard let base = parsePercent() else { return nil }
            guard peekSymbol(in: "^") != nil else { return base }
            position += 1
            guard let exponent = parseUnary() else { return nil }  // right-associative; 2^-1 works
            return Foundation.pow(base, exponent)
        }

        mutating func parsePercent() -> Double? {
            guard var value = parsePrimary() else { return nil }
            while peekSymbol(in: "%") != nil {
                position += 1
                value /= 100
            }
            return value
        }

        mutating func parsePrimary() -> Double? {
            guard position < tokens.count else { return nil }
            let token = tokens[position]
            position += 1
            switch token {
            case .number(let value):
                return value
            case .symbol("("):
                guard let value = parseExpression(), peekSymbol(in: ")") != nil else { return nil }
                position += 1
                return value
            case .name(let name):
                if let constant = Calculator.constants[name] { return constant }
                guard let function = Calculator.functions[name], let argument = parsePrimary() else { return nil }
                return function(argument)
            case .symbol:
                return nil
            }
        }

        func peekSymbol(in symbols: String) -> Character? {
            guard position < tokens.count, case .symbol(let symbol) = tokens[position], symbols.contains(symbol) else { return nil }
            return symbol
        }
    }
}

// MARK: - Unit conversion

/// "10 km to mi", "100 f in c", "5 kg to lb", "2 gb to mb".
enum UnitConversion {
    private static let units: [String: Dimension] = [
        // Length
        "mm": UnitLength.millimeters, "cm": UnitLength.centimeters, "m": UnitLength.meters,
        "km": UnitLength.kilometers, "in": UnitLength.inches, "inch": UnitLength.inches, "inches": UnitLength.inches,
        "ft": UnitLength.feet, "foot": UnitLength.feet, "feet": UnitLength.feet, "yd": UnitLength.yards,
        "mi": UnitLength.miles, "mile": UnitLength.miles, "miles": UnitLength.miles,
        // Mass
        "g": UnitMass.grams, "kg": UnitMass.kilograms, "oz": UnitMass.ounces, "lb": UnitMass.pounds,
        "lbs": UnitMass.pounds, "st": UnitMass.stones,
        // Temperature
        "c": UnitTemperature.celsius, "°c": UnitTemperature.celsius, "celsius": UnitTemperature.celsius,
        "f": UnitTemperature.fahrenheit, "°f": UnitTemperature.fahrenheit, "fahrenheit": UnitTemperature.fahrenheit,
        "k": UnitTemperature.kelvin, "kelvin": UnitTemperature.kelvin,
        // Volume
        "ml": UnitVolume.milliliters, "l": UnitVolume.liters, "gal": UnitVolume.gallons,
        "floz": UnitVolume.fluidOunces, "cup": UnitVolume.cups, "cups": UnitVolume.cups,
        // Speed
        "kmh": UnitSpeed.kilometersPerHour, "km/h": UnitSpeed.kilometersPerHour, "mph": UnitSpeed.milesPerHour,
        "m/s": UnitSpeed.metersPerSecond, "knots": UnitSpeed.knots,
        // Data
        "b": UnitInformationStorage.bytes, "kb": UnitInformationStorage.kilobytes, "mb": UnitInformationStorage.megabytes,
        "gb": UnitInformationStorage.gigabytes, "tb": UnitInformationStorage.terabytes,
        // Time
        "s": UnitDuration.seconds, "sec": UnitDuration.seconds, "min": UnitDuration.minutes,
        "h": UnitDuration.hours, "hr": UnitDuration.hours, "hours": UnitDuration.hours,
    ]

    static func convert(_ text: String) -> QuickAnswer? {
        let pattern = /^\s*(-?[\d.,]+)\s*([^\s\d]+)\s+(?:to|in|as)\s+([^\s\d]+)\s*$/
        guard let match = text.lowercased().wholeMatch(of: pattern),
              let value = Double(match.1.replacingOccurrences(of: ",", with: "")),
              let from = units[String(match.2)], let to = units[String(match.3)],
              type(of: from) == type(of: to)
        else { return nil }
        let converted = Measurement(value: value, unit: from).converted(to: to)
        return QuickAnswer(
            question: "\(QuickAnswer.format(value)) \(match.2) in \(match.3)",
            answer: "\(QuickAnswer.format((converted.value * 100).rounded() / 100)) \(match.3)"
        )
    }
}
