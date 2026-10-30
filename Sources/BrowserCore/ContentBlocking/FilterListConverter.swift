import Foundation

/// Converts Adblock Plus–syntax filter lists (EasyList, EasyPrivacy, our own
/// lists) into WebKit content rules.
///
/// Only what WebKit can express faithfully is converted. Regex filters,
/// extended CSS, scriptlets, popup/redirect/csp options and rules that mix
/// included and excluded domains are skipped: an approximated rule blocks too
/// much and breaks sites.
public enum FilterListConverter {
    public struct Output: Sendable {
        public var rules: [ContentRule]
        /// Filter lines that couldn't be expressed (or didn't fit) and were dropped.
        public var skipped: Int
    }

    /// Bump when conversion output changes, so cached compiled lists are rebuilt.
    public static let version = 2

    /// WebKit compiles far larger lists, but Safari caps content blockers at
    /// 150k rules and compile time grows with size.
    public static let defaultMaxRules = 150_000

    public static func convert(_ text: String, includeCosmetic: Bool = true, maxRules: Int = defaultMaxRules) -> Output {
        var parser = Parser(includeCosmetic: includeCosmetic)
        for line in text.split(whereSeparator: \.isNewline) {
            parser.consume(line)
        }
        return parser.finish(maxRules: maxRules)
    }
}

// MARK: - Parser

private struct Parser {
    let includeCosmetic: Bool
    var blocking: [ContentRule] = []
    var exceptions: [ContentRule] = []
    var genericSelectors: [String] = []
    var seenGenericSelectors: Set<String> = []
    /// Selector → domains where an `#@#` exception turns it off.
    var selectorExceptions: [String: [String]] = [:]
    var scopedSelectors: [DomainScope: [String]] = [:]
    var scopeOrder: [DomainScope] = []
    var skipped = 0

    /// Site-specific selectors joined into one `css-display-none` rule.
    /// (Site-wide ones stay one per rule: WebKit merges those into a single
    /// stylesheet itself, and one invalid selector in a hand-made group
    /// silently drops the whole group.)
    static let selectorsPerRule = 50
    /// WebKit hits a RELEASE_ASSERT at 65,535 domain-conditioned `.*` rules
    /// in one list; stay well below it.
    static let maxScopedCosmeticRules = 60_000

    init(includeCosmetic: Bool) {
        self.includeCosmetic = includeCosmetic
    }

    mutating func consume(_ raw: Substring) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("!"), !line.hasPrefix("[") else { return }

        switch CosmeticMarker(in: line) {
        case .hide(let domains, let selector):
            consumeCosmetic(domains: domains, selector: selector, isException: false)
        case .exception(let domains, let selector):
            consumeCosmetic(domains: domains, selector: selector, isException: true)
        case .unsupported:
            skipped += 1
        case nil:
            guard let converted = NetworkFilter.rules(from: line) else {
                skipped += 1
                return
            }
            if converted.isException {
                exceptions += converted.rules
            } else {
                blocking += converted.rules
            }
        }
    }

    mutating func consumeCosmetic(domains: Substring, selector: Substring, isException: Bool) {
        guard includeCosmetic else { return }
        let selector = String(selector)
        guard Selector.isSupported(selector), let scope = DomainScope(parsing: domains, separator: ",") else {
            skipped += 1
            return
        }

        if isException {
            // "Not on these sites" (applied in finish); "only on these" isn't expressible.
            guard !scope.ifDomain.isEmpty, scope.unlessDomain.isEmpty else {
                skipped += 1
                return
            }
            selectorExceptions[selector, default: []] += scope.ifDomain
        } else if scope.isEmpty {
            if seenGenericSelectors.insert(selector).inserted {
                genericSelectors.append(selector)
            }
        } else {
            if scopedSelectors[scope] == nil {
                scopeOrder.append(scope)
            }
            scopedSelectors[scope, default: []].append(selector)
        }
    }

    func finish(maxRules: Int) -> FilterListConverter.Output {
        var cosmetic: [ContentRule] = []
        var scoped: [ContentRule] = []
        for selector in genericSelectors {
            if let exempt = selectorExceptions[selector] {
                scoped.append(Self.hide(selector, trigger: .init(urlFilter: ".*", unlessDomain: Array(Set(exempt)).sorted())))
            } else {
                cosmetic.append(Self.hide(selector, trigger: .init(urlFilter: ".*")))
            }
        }
        var unexpressible = 0
        for scope in scopeOrder {
            var selectors: [String] = []
            for selector in scopedSelectors[scope, default: []] {
                guard let exempt = selectorExceptions[selector] else {
                    selectors.append(selector)
                    continue
                }
                if scope.ifDomain.isEmpty {
                    // Everywhere but some sites: the exception's sites join them.
                    let unless = Array(Set(scope.unlessDomain + exempt)).sorted()
                    scoped.append(Self.hide(selector, trigger: .init(urlFilter: ".*", unlessDomain: unless)))
                } else if scope.ifDomain.contains(where: { domain in exempt.contains { Self.overlaps($0, domain) } }) {
                    // Hidden on a site but shown on part of it: WebKit can't say
                    // that (if- and unless-domain don't mix), so leave it out
                    // rather than break the page the exception was written for.
                    unexpressible += 1
                } else {
                    selectors.append(selector)
                }
            }
            for chunk in selectors.chunked(into: Self.selectorsPerRule) {
                scoped.append(Self.hide(chunk.joined(separator: ", "), trigger: scope.trigger(urlFilter: ".*")))
            }
        }
        let scopedDropped = max(0, scoped.count - Self.maxScopedCosmeticRules)
        cosmetic += scoped.prefix(Self.maxScopedCosmeticRules)

        // Exceptions must always ship (and come last: ignore-previous-rules only
        // cancels rules before it). Then network blocking, then cosmetic.
        let budget = max(0, maxRules - exceptions.count)
        let network = Array(blocking.prefix(budget))
        let hiding = Array(cosmetic.prefix(max(0, budget - network.count)))
        let dropped = (blocking.count - network.count) + (cosmetic.count - hiding.count) + scopedDropped
        return .init(rules: network + hiding + exceptions, skipped: skipped + dropped + unexpressible)
    }

    /// Whether two normalized domains (`*example.com`) cover some of the
    /// same sites: equal, or one a subdomain of the other.
    static func overlaps(_ a: String, _ b: String) -> Bool {
        let a = a.drop { $0 == "*" }, b = b.drop { $0 == "*" }
        return a == b || a.hasSuffix("." + b) || b.hasSuffix("." + a)
    }

    static func hide(_ selector: String, trigger: ContentRule.Trigger) -> ContentRule {
        ContentRule(trigger: trigger, action: .init(type: .cssDisplayNone, selector: selector))
    }
}

// MARK: - Cosmetic filters

private enum CosmeticMarker {
    case hide(domains: Substring, selector: Substring)
    case exception(domains: Substring, selector: Substring)
    /// Extended CSS (`#?#`), CSS injection (`#$#`), JS (`#%#`) and their exceptions.
    case unsupported

    init?(in line: String) {
        guard let hash = line.firstIndex(of: "#") else { return nil }
        let rest = line[hash...]
        let domains = line[..<hash]
        if rest.hasPrefix("##") {
            self = .hide(domains: domains, selector: rest.dropFirst(2))
        } else if rest.hasPrefix("#@#") {
            self = .exception(domains: domains, selector: rest.dropFirst(3))
        } else if ["#?#", "#$#", "#%#", "#@?#", "#@$#", "#@%#"].contains(where: { rest.hasPrefix($0) }) {
            self = .unsupported
        } else {
            return nil
        }
    }
}

private enum Selector {
    static let allowedPseudoClasses: Set<String> = [
        "not", "has", "is", "where", "root", "empty",
        "first-child", "last-child", "only-child", "nth-child", "nth-last-child",
        "first-of-type", "last-of-type", "only-of-type", "nth-of-type", "nth-last-of-type",
    ]

    /// Conservative check: a single invalid selector makes WebKit reject the
    /// whole rule list, so anything unusual is refused.
    static func isSupported(_ selector: String) -> Bool {
        guard let first = selector.first, selector.utf8.count < 4_000 else { return false }
        // `+js(...)` scriptlets and `^` HTML filters aren't CSS.
        guard first != "+", first != "^" else { return false }
        guard selector.unicodeScalars.allSatisfy({ $0.isASCII && $0 != "\\" }) else { return false }

        var brackets = 0
        var parens = 0
        var quote: Character?
        var index = selector.startIndex
        while index < selector.endIndex {
            let character = selector[index]
            if let open = quote {
                if character == open { quote = nil }
            } else {
                switch character {
                case "\"", "'": quote = character
                case "[": brackets += 1
                case "]": brackets -= 1
                case "(": parens += 1
                case ")": parens -= 1
                case ":" where brackets == 0:
                    var cursor = selector.index(after: index)
                    // `::before` etc.: pseudo-elements can't be hidden this way.
                    if cursor < selector.endIndex, selector[cursor] == ":" { return false }
                    var name = ""
                    while cursor < selector.endIndex, selector[cursor].isLetter || selector[cursor] == "-" {
                        name.append(selector[cursor])
                        cursor = selector.index(after: cursor)
                    }
                    guard allowedPseudoClasses.contains(name) else { return false }
                    index = cursor
                    continue
                default:
                    break
                }
                if brackets < 0 || parens < 0 { return false }
            }
            index = selector.index(after: index)
        }
        return quote == nil && brackets == 0 && parens == 0
    }
}

// MARK: - Domains

/// `example.com,~ads.example.com` style domain lists, as WebKit triggers.
private struct DomainScope: Hashable {
    var ifDomain: [String] = []
    var unlessDomain: [String] = []

    var isEmpty: Bool { ifDomain.isEmpty && unlessDomain.isEmpty }

    /// Returns nil when the list can't be represented: WebKit forbids mixing
    /// if-domain with unless-domain, and dropping an unparsable *exclusion*
    /// would apply the rule where the list author said not to.
    init?(parsing text: Substring, separator: Character) {
        var droppedInclusion = false
        for entry in text.split(separator: separator) {
            let isExclusion = entry.hasPrefix("~")
            guard let domain = Self.normalized(isExclusion ? entry.dropFirst() : entry) else {
                if isExclusion { return nil }
                droppedInclusion = true
                continue
            }
            if isExclusion {
                unlessDomain.append(domain)
            } else {
                ifDomain.append(domain)
            }
        }
        if !ifDomain.isEmpty, !unlessDomain.isEmpty { return nil }
        // Every inclusion was unparsable: converting would make the rule global.
        if droppedInclusion, ifDomain.isEmpty { return nil }
    }

    func trigger(urlFilter: String) -> ContentRule.Trigger {
        .init(
            urlFilter: urlFilter,
            ifDomain: ifDomain.isEmpty ? nil : ifDomain,
            unlessDomain: unlessDomain.isEmpty ? nil : unlessDomain
        )
    }

    /// `Example.com` → `*example.com` (the `*` makes WebKit include subdomains).
    static func normalized(_ raw: Substring) -> String? {
        let domain = raw.lowercased()
        guard !domain.isEmpty, domain.contains("."),
              domain.unicodeScalars.allSatisfy({ CharacterSet.domainCharacters.contains($0) }),
              !domain.hasPrefix("."), !domain.hasSuffix(".")
        else { return nil }
        return "*" + domain
    }
}

private extension CharacterSet {
    static let domainCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
}

// MARK: - Network filters

private enum NetworkFilter {
    /// WebKit resource types per filter option. XHR/fetch/WebSocket/ping are
    /// all "raw" in WebKit's oldest, universally supported vocabulary.
    static let typeMap: [String: String] = [
        "script": "script", "image": "image", "stylesheet": "style-sheet", "css": "style-sheet",
        "font": "font", "media": "media", "xmlhttprequest": "raw", "xhr": "raw",
        "websocket": "raw", "ping": "raw", "other": "raw",
    ]
    /// Everything except documents, so an untyped filter never blocks a page
    /// the user navigates to (subframe documents get their own rule).
    static let subresourceTypes = ["font", "image", "media", "raw", "script", "style-sheet", "svg-document"]

    struct Options {
        var loadType: [String]?
        var caseSensitive = false
        var scope: DomainScope?
        var types: Set<String> = []
        var excludedTypes: Set<String> = []
        var subdocument = false
        var excludesSubdocument = false
        var document = false

        /// False for options we can't honor; the whole filter is then skipped.
        mutating func apply(_ option: Substring) -> Bool {
            let parts = option.split(separator: "=", maxSplits: 1)
            guard let rawName = parts.first else { return false }
            let name = rawName.lowercased()
            switch name {
            case "third-party", "3p":
                loadType = ["third-party"]
            case "~third-party", "first-party", "1p", "~3p":
                loadType = ["first-party"]
            case "match-case":
                caseSensitive = true
            case "important", "~object":
                break
            case "domain", "from":
                guard parts.count == 2, let parsed = DomainScope(parsing: parts[1], separator: "|"), !parsed.isEmpty else { return false }
                scope = parsed
            case "document", "doc":
                document = true
            case "subdocument", "frame":
                subdocument = true
            case "~subdocument", "~frame":
                excludesSubdocument = true
            default:
                if let type = typeMap[name] {
                    types.insert(type)
                } else if name.hasPrefix("~"), let type = typeMap[String(name.dropFirst())] {
                    excludedTypes.insert(type)
                } else {
                    return false
                }
            }
            return true
        }
    }

    static func rules(from line: String) -> (rules: [ContentRule], isException: Bool)? {
        var body = Substring(line)
        let isException = body.hasPrefix("@@")
        if isException { body = body.dropFirst(2) }

        var options = Options()
        if let dollar = body.lastIndex(of: "$") {
            let list = body[body.index(after: dollar)...]
            // Options we can't even tokenize (e.g. `$csp=script-src 'none'`).
            guard isOptionList(list) else { return nil }
            for option in list.split(separator: ",") {
                guard options.apply(option) else { return nil }
            }
            body = body[..<dollar]
        }

        let action = ContentRule.Action(type: isException ? .ignorePreviousRules : .block)

        if options.document {
            // `@@||example.com^$document` turns blocking off on that site's
            // pages. Blocking whole pages isn't something we do silently.
            guard isException, let domain = plainDomain(body) else { return nil }
            return ([ContentRule(trigger: .init(urlFilter: ".*", ifDomain: ["*" + domain]), action: action)], true)
        }

        guard let urlFilter = urlFilter(for: body) else { return nil }
        // A match-anything pattern is only acceptable when scoped to sites;
        // `*$script` would otherwise block every script on the web.
        if urlFilter == ".*", options.scope == nil { return nil }

        var base = options.scope?.trigger(urlFilter: urlFilter) ?? .init(urlFilter: urlFilter)
        base.urlFilterIsCaseSensitive = options.caseSensitive ? true : nil
        base.loadType = options.loadType

        var subresource: [String]
        if !options.types.isEmpty {
            subresource = options.types.sorted()
        } else if !options.excludedTypes.isEmpty {
            subresource = subresourceTypes.filter { !options.excludedTypes.contains($0) }
        } else {
            subresource = options.subdocument ? [] : subresourceTypes
        }
        let blocksFrames = options.subdocument || (options.types.isEmpty && !options.excludesSubdocument)

        var rules: [ContentRule] = []
        if !subresource.isEmpty {
            var trigger = base
            trigger.resourceType = subresource
            rules.append(ContentRule(trigger: trigger, action: action))
        }
        if blocksFrames {
            var trigger = base
            trigger.resourceType = ["document"]
            trigger.loadContext = ["child-frame"]
            rules.append(ContentRule(trigger: trigger, action: action))
        }
        return rules.isEmpty ? nil : (rules, isException)
    }

    /// Filter options look like `script,third-party,domain=a.com|~b.com`.
    static func isOptionList(_ text: Substring) -> Bool {
        guard let first = text.first, first.isLetter || first == "~" else { return false }
        return text.unicodeScalars.allSatisfy { CharacterSet.optionCharacters.contains($0) }
    }

    /// ABP pattern → WebKit url-filter regex. WebKit's regex subset has no
    /// alternation, so `^` becomes a required separator character. One
    /// unsupported regex fails the whole list, so risky characters are refused.
    static func urlFilter(for pattern: Substring) -> String? {
        var pattern = pattern
        if pattern.count > 2, pattern.hasPrefix("/"), pattern.hasSuffix("/") { return nil }

        var regex = ""
        if pattern.hasPrefix("||") {
            regex = "^[^:]+://+([^:/]+\\.)?"
            pattern = pattern.dropFirst(2)
        } else if pattern.hasPrefix("|") {
            regex = "^"
            pattern = pattern.dropFirst()
        }
        var anchoredAtEnd = false
        if pattern.hasSuffix("|") {
            anchoredAtEnd = true
            pattern = pattern.dropLast()
        }
        if regex.isEmpty {
            while pattern.hasPrefix("*") { pattern = pattern.dropFirst() }
        }
        if !anchoredAtEnd {
            while pattern.hasSuffix("*") { pattern = pattern.dropLast() }
        }
        // A tiny unanchored pattern ("ad", "/x") matches far too much.
        if regex.isEmpty, !anchoredAtEnd, !pattern.isEmpty, pattern.count < 4 { return nil }

        for scalar in pattern.unicodeScalars {
            guard scalar.isASCII else { return nil }
            switch scalar {
            case "*": regex += ".*"
            case "^": regex += "[/:?=&]"
            case ".", "+", "?", "$": regex += "\\" + String(scalar)
            case "|", "{", "}", "(", ")", "[", "]", "\\": return nil
            default: regex.unicodeScalars.append(scalar)
            }
        }
        if anchoredAtEnd { regex += "$" }
        return regex.isEmpty ? ".*" : regex
    }

    /// `||example.com^` → `example.com`; nil for anything with a path or wildcard.
    static func plainDomain(_ pattern: Substring) -> String? {
        guard pattern.hasPrefix("||") else { return nil }
        var domain = pattern.dropFirst(2)
        for suffix in ["^|", "^", "/"] where domain.hasSuffix(suffix) {
            domain = domain.dropLast(suffix.count)
            break
        }
        return DomainScope.normalized(domain).map { String($0.dropFirst()) }
    }
}

private extension CharacterSet {
    static let optionCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789~-_=|.,*")
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
