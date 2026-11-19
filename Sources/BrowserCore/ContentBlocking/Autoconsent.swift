import Foundation

/// The app's half of autoconsent v2, the part with no WebKit in it.
///
/// DuckDuckGo's autoconsent library runs in an isolated world in every frame
/// and asks the app two things: which rules apply to this frame (`init`), and
/// what one of its page-state checks says (`eval`). This is DuckDuckGo's own
/// extension design, with the app in the background page's place.
public enum Autoconsent {
    /// What the library sends. Anything else, or anything malformed, is dropped.
    public enum Message: Equatable, Sendable {
        /// A frame at this http(s) address wants its rules.
        case initialize(url: String)
        /// Run snippet `snippet` in the frame's page world, answer with `id`.
        case evaluate(id: String, snippet: String)

        public init?(_ body: Any) {
            guard let body = body as? [String: Any], let type = body["type"] as? String else { return nil }
            switch type {
            case "init":
                // `location.href`, which is always serialized: the prefix is the scheme.
                guard let url = body["url"] as? String, url.utf16.count <= 8_192,
                      url.lowercased().hasPrefix("https://") || url.lowercased().hasPrefix("http://")
                else { return nil }
                self = .initialize(url: url)
            case "eval":
                guard let id = body["id"] as? String, (1...64).contains(id.count),
                      let snippet = body["snippetId"] as? String, (1...128).contains(snippet.count)
                else { return nil }
                self = .evaluate(id: id, snippet: snippet)
            default:
                return nil
            }
        }
    }

    /// The library's settings. As in v1 (its standalone build) apart from
    /// `isMainWorld`, which sends page-state checks to the app, and logging.
    public static let configJSON = """
        {"enabled":true,"autoAction":"optOut","disabledCmps":[],"enablePrehide":true,"enableCosmeticRules":true,\
        "enableGeneratedRules":true,"enableHeuristicDetection":true,"heuristicMode":"tier2",\
        "enablePopupMutationObserver":false,"detectRetries":20,"isMainWorld":false,"prehideTimeout":2000,\
        "logs":{"lifecycle":false,"rulesteps":false,"detectionsteps":false,"evals":false,"errors":true,"messages":false,"waits":false}}
        """

    /// The `initResp` message for a frame: settings plus only its rules.
    public static func initReply(rules: Rules, url: String, mainFrame: Bool) -> String {
        #"{"type":"initResp","config":\#(configJSON),"rules":{"autoconsent":[],"compact":\#(rules.select(url: url, mainFrame: mainFrame).json)}}"#
    }
}

// MARK: - Rules

extension Autoconsent {
    /// autoconsent's compact rule list (`rules/compact-rules.json`), filtered
    /// per frame exactly as its own `filterCompactRules` does: a subframe gets
    /// the few rules that run in frames and match its address; a main frame
    /// gets the generic rules (common consent platforms, found on any site)
    /// plus any site-specific rule whose pattern matches. Rules are kept as
    /// JSON text, so answering a frame is string assembly, not encoding.
    public struct Rules: Sendable {
        struct Rule: Sendable {
            let name: String
            let json: String
            /// Tens digit: main frame, units: subframes (0 no, 1 yes, 2 either).
            let context: Int
            let pattern: NSRegularExpression?
            let hasPattern: Bool
            let strings: [Int]
        }

        public struct Selection: Sendable {
            fileprivate let rules: Rules
            let indices: [Int]
            /// Length of the `s` array the frame gets.
            public let stringCount: Int
            /// Strings it keeps; nil keeps all, others become "".
            let used: Set<Int>?

            public var ruleNames: [String] { indices.map { rules.rules[$0].name } }
            public var usedStringCount: Int {
                (0..<stringCount).count(where: { (used?.contains($0) ?? true) && rules.strings[$0] != #""""# })
            }

            public var json: String {
                used == nil ? rules.genericOnlyJSON : assembled
            }

            fileprivate var assembled: String {
                var out = #"{"v":\#(rules.version),"s":["#
                for index in 0..<stringCount {
                    if index > 0 { out += "," }
                    out += used.map { $0.contains(index) } ?? true ? rules.strings[index] : #""""#
                }
                out += #"],"r":["#
                out += indices.map { rules.rules[$0].json }.joined(separator: ",")
                out += "]}"
                return out
            }
        }

        let version: Int
        /// Each string already encoded as a JSON literal.
        let strings: [String]
        let rules: [Rule]
        let genericRules: Range<Int>
        let frameRules: Range<Int>
        let specificRules: Range<Int>
        let genericStringEnd: Int
        let frameStringEnd: Int
        /// Patterns that NSRegularExpression couldn't read (none in 16.61.0).
        public let unreadablePatterns: [String]
        /// What most main frames get, built once.
        private(set) var genericOnlyJSON = ""

        public enum LoadError: Error { case malformed(String) }

        public init(data: Data) throws {
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = root["v"] as? Int,
                  let strings = root["s"] as? [String],
                  let rules = root["r"] as? [[Any]],
                  let index = root["index"] as? [String: Any]
            else { throw LoadError.malformed("top level") }
            func range(_ key: String) throws -> Range<Int> {
                guard let bounds = index[key] as? [Int], bounds.count == 2, 0 <= bounds[0], bounds[0] <= bounds[1], bounds[1] <= rules.count
                else { throw LoadError.malformed(key) }
                return bounds[0]..<bounds[1]
            }
            func end(_ key: String) throws -> Int {
                guard let end = index[key] as? Int, 0 <= end, end <= strings.count else { throw LoadError.malformed(key) }
                return end
            }
            self.version = version
            genericRules = try range("genericRuleRange")
            frameRules = try range("frameRuleRange")
            specificRules = try range("specificRuleRange")
            genericStringEnd = try end("genericStringEnd")
            frameStringEnd = try end("frameStringEnd")

            let options: JSONSerialization.WritingOptions = [.withoutEscapingSlashes, .fragmentsAllowed]
            self.strings = try strings.map { String(decoding: try JSONSerialization.data(withJSONObject: $0, options: options), as: UTF8.self) }
            var unreadable: [String] = []
            var patterns: [String: NSRegularExpression] = [:]
            self.rules = try rules.enumerated().map { offset, rule in
                guard rule.count >= 10, let name = rule[1] as? String, let pattern = rule[3] as? String, let context = rule[4] as? Int,
                      let prehide = rule[5] as? [Int]
                else { throw LoadError.malformed("rule \(offset)") }
                var used = Set(prehide)
                for steps in rule[6...9] {
                    Self.collectStrings(in: steps, into: &used)
                }
                guard used.allSatisfy({ 0 <= $0 && $0 < strings.count }) else { throw LoadError.malformed("strings of \(name)") }
                var regex: NSRegularExpression?
                if !pattern.isEmpty {
                    regex = patterns[pattern] ?? (try? NSRegularExpression(pattern: pattern))
                    if regex == nil { unreadable.append(pattern) }
                    patterns[pattern] = regex
                }
                let json = String(decoding: try JSONSerialization.data(withJSONObject: rule, options: options), as: UTF8.self)
                return Rule(name: name, json: json, context: context, pattern: regex, hasPattern: !pattern.isEmpty, strings: used.sorted())
            }
            unreadablePatterns = unreadable
            genericOnlyJSON = genericOnly.assembled
        }

        private var genericOnly: Selection {
            Selection(rules: self, indices: Array(genericRules), stringCount: genericStringEnd, used: nil)
        }

        /// The string ids a rule's steps point at (`clearUnusedStrings`).
        private static func collectStrings(in steps: Any, into used: inout Set<Int>) {
            let keys = ["e", "v", "c", "k", "w", "wv", "h", "cc"]
            guard let steps = steps as? [Any] else { return }
            for case let step as [String: Any] in steps {
                for key in keys {
                    if let id = step[key] as? Int { used.insert(id) }
                }
                if let condition = step["if"] { collectStrings(in: [condition], into: &used) }
                for key in ["then", "else", "any"] {
                    if let nested = step[key] { collectStrings(in: nested, into: &used) }
                }
            }
        }

        /// `shouldRunRuleInContext`.
        private func shouldRun(_ rule: Rule, url: String, mainFrame: Bool) -> Bool {
            if mainFrame && rule.context == 1 { return false }
            if !mainFrame && [20, 22, 10, 12].contains(rule.context) { return false }
            guard rule.hasPattern else { return true }
            // A pattern we can't read never matches, so its rule stays out.
            guard let pattern = rule.pattern else { return false }
            return pattern.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
        }

        /// `filterCompactRules` for one frame.
        public func select(url: String, mainFrame: Bool) -> Selection {
            if !mainFrame {
                return cleared(frameRules.filter { shouldRun(rules[$0], url: url, mainFrame: false) }, strings: frameStringEnd)
            }
            let specific = specificRules.filter { shouldRun(rules[$0], url: url, mainFrame: true) }
            if !specific.isEmpty {
                return cleared(Array(genericRules) + specific, strings: strings.count)
            }
            return genericOnly
        }

        /// `clearUnusedStrings`: cut after the last string used, blank the rest.
        private func cleared(_ indices: [Int], strings count: Int) -> Selection {
            let used = Set(indices.flatMap { rules[$0].strings })
            let length = used.max().map { min(count, $0 + 1) } ?? 0
            return Selection(rules: self, indices: indices, stringCount: length, used: used)
        }
    }
}

// MARK: - Snippets

extension Autoconsent {
    /// The page-state checks that ship with autoconsent's rules, by id.
    ///
    /// Trust boundary: a check has to run in the page's own world, since it
    /// reads the consent platform's globals (`window.Didomi`, `Cookiebot`…).
    /// The isolated world asks for one by id only and never sends code; the
    /// app looks the id up in this table, generated from the same autoconsent
    /// release as the rules (`scripts/vendor-autoconsent.sh`), and an unknown
    /// id runs nothing. The page can't post to the handler at all, as it only
    /// exists in the isolated world. What returns is one boolean, which a page
    /// can of course influence, but only for how its own pop-up is handled.
    public struct Snippets: Sendable {
        let table: [String: String]

        public init(data: Data) throws {
            guard let table = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
                throw Rules.LoadError.malformed("snippets")
            }
            self.table = table
        }

        public var count: Int { table.count }

        /// The script to evaluate for `id`, or nil if autoconsent has no such
        /// snippet. Errors thrown by the page's code count as false.
        public func script(for id: String) -> String? {
            table[id].map { "(() => { try { return !!(\($0)); } catch (e) { return false; } })()" }
        }
    }
}
