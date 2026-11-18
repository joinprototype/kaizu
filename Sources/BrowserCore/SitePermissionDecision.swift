/// The answer to a request for one or more devices on a single site.
public enum SitePermissionDecision: Equatable {
    case allow, deny
    case ask([String])

    public static func resolve(_ devices: [String], saved: [String: Bool]) -> Self {
        if devices.contains(where: { saved[$0] == false }) { return .deny }
        let unanswered = devices.filter { saved[$0] == nil }
        return unanswered.isEmpty ? .allow : .ask(unanswered)
    }
}
