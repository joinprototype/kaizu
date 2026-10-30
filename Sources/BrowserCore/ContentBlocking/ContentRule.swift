import Foundation

/// One WebKit content rule, in the JSON shape `WKContentRuleListStore` compiles.
public struct ContentRule: Encodable, Equatable, Sendable {
    public struct Trigger: Encodable, Equatable, Sendable {
        public var urlFilter: String
        public var urlFilterIsCaseSensitive: Bool?
        public var ifDomain: [String]?
        public var unlessDomain: [String]?
        public var resourceType: [String]?
        public var loadType: [String]?
        public var loadContext: [String]?

        public init(
            urlFilter: String,
            urlFilterIsCaseSensitive: Bool? = nil,
            ifDomain: [String]? = nil,
            unlessDomain: [String]? = nil,
            resourceType: [String]? = nil,
            loadType: [String]? = nil,
            loadContext: [String]? = nil
        ) {
            self.urlFilter = urlFilter
            self.urlFilterIsCaseSensitive = urlFilterIsCaseSensitive
            self.ifDomain = ifDomain
            self.unlessDomain = unlessDomain
            self.resourceType = resourceType
            self.loadType = loadType
            self.loadContext = loadContext
        }

        enum CodingKeys: String, CodingKey {
            case urlFilter = "url-filter"
            case urlFilterIsCaseSensitive = "url-filter-is-case-sensitive"
            case ifDomain = "if-domain"
            case unlessDomain = "unless-domain"
            case resourceType = "resource-type"
            case loadType = "load-type"
            case loadContext = "load-context"
        }
    }

    public enum ActionType: String, Encodable, Sendable {
        case block
        case cssDisplayNone = "css-display-none"
        case ignorePreviousRules = "ignore-previous-rules"
    }

    public struct Action: Encodable, Equatable, Sendable {
        public var type: ActionType
        public var selector: String?

        public init(type: ActionType, selector: String? = nil) {
            self.type = type
            self.selector = selector
        }
    }

    public var trigger: Trigger
    public var action: Action

    public init(trigger: Trigger, action: Action) {
        self.trigger = trigger
        self.action = action
    }
}

extension Array where Element == ContentRule {
    /// The rule list as the JSON string `WKContentRuleListStore` expects.
    public func encodedJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}
