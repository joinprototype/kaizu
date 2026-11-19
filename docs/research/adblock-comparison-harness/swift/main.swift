import Foundation
import WebKit
import AppKit


// MARK: - Content-rule model matcher (semantics verified against WKWebView, see report)
struct MRule {
    var regex: NSRegularExpression?
    var pattern: String
    var block: Bool
    var typeSet: Set<String>?
    var loadType: String?
    var context: String?
    var ifDomain: [String]?
    var unlessDomain: [String]?
}

func registrable(_ host: String) -> String {
    let p = host.split(separator: ".").map(String.init)
    guard p.count > 2 else { return host }
    let sld: Set<String> = ["co", "com", "org", "net", "gov", "ac", "edu"]
    if p[p.count - 1].count == 2, sld.contains(p[p.count - 2]) { return p.suffix(3).joined(separator: ".") }
    return p.suffix(2).joined(separator: ".")
}

func expandTypes(_ list: [String]) -> Set<String> {
    var out = Set<String>()
    for t in list {
        if t == "raw" { out.formUnion(["fetch", "ping", "websocket", "other"]) } else { out.insert(t) }
    }
    return out
}

func domainMatches(_ entry: String, _ host: String) -> Bool {
    if entry.hasPrefix("*") {
        let d = String(entry.dropFirst())
        return host == d || host.hasSuffix("." + d)
    }
    return host == entry
}

func loadRules(_ path: String) -> [MRule] {
    let data = try! Data(contentsOf: URL(fileURLWithPath: path))
    let arr = try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]
    var out: [MRule] = []
    for r in arr {
        let a = r["action"] as! [String: Any]
        let t = r["trigger"] as! [String: Any]
        let type = a["type"] as! String
        guard type == "block" || type == "ignore-previous-rules" else { continue }
        let rt = t["resource-type"] as? [String]
        let ts: Set<String>? = (rt == nil || rt!.isEmpty) ? nil : expandTypes(rt!)
        out.append(MRule(
            regex: nil, pattern: t["url-filter"] as! String, block: type == "block", typeSet: ts,
            loadType: (t["load-type"] as? [String])?.first, context: (t["load-context"] as? [String])?.first,
            ifDomain: t["if-domain"] as? [String], unlessDomain: t["unless-domain"] as? [String]))
        let cs = (t["url-filter-is-case-sensitive"] as? Bool) ?? false
        out[out.count - 1].regex = try? NSRegularExpression(pattern: t["url-filter"] as! String, options: cs ? [] : [.caseInsensitive])
    }
    return out
}

func decide(_ rules: [MRule], url: String, top: String, abpType: String) -> (Bool, String) {
    let u = URL(string: url), tu = URL(string: top)
    let host = u?.host ?? "", topHost = tu?.host ?? ""
    let isTop = abpType == "document"
    var tokens: Set<String>
    switch abpType {
    case "script": tokens = ["script"]
    case "image": tokens = ["image"]
    case "stylesheet": tokens = ["style-sheet"]
    case "xmlhttprequest": tokens = ["fetch"]
    case "subdocument", "document": tokens = ["document"]
    case "ping": tokens = ["other", "ping"]
    default: tokens = [abpType]
    }
    let third = registrable(host) != registrable(topHost)
    var blocked = false
    var by = ""
    let range = NSRange(url.startIndex..., in: url)
    for r in rules {
        if let ts = r.typeSet, ts.isDisjoint(with: tokens) { continue }
        if let lt = r.loadType, (lt == "third-party") != third { continue }
        if let c = r.context, (c == "top-frame") != isTop { continue }
        if let d = r.ifDomain, !d.contains(where: { domainMatches($0, topHost) }) { continue }
        if let d = r.unlessDomain, d.contains(where: { domainMatches($0, topHost) }) { continue }
        guard let re = r.regex, re.firstMatch(in: url, options: [], range: range) != nil else { continue }
        if r.block { blocked = true; by = r.pattern } else { blocked = false; by = "" }
    }
    return (blocked, by)
}


func fail(_ s: String) -> Never { FileHandle.standardError.write(Data((s + "\n").utf8)); exit(1) }
let args = CommandLine.arguments
guard args.count >= 2 else { fail("usage") }

switch args[1] {
case "convert":
    // convert out.json lines.tsv list...
    var text = ""
    var tsv = ""
    for path in args[4...] {
        let t = try! String(contentsOfFile: path, encoding: .utf8)
        let name = (path as NSString).lastPathComponent
        for sub in t.split(whereSeparator: \.isNewline) {
            let line = sub.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[") { continue }
            let o = FilterListConverter.convert(String(sub), maxRules: 10_000_000)
            let status = o.skipped > 0 ? "skip" : (o.rules.isEmpty ? "noop" : "ok")
            tsv += "\(name)\t\(status)\t\(o.rules.count)\t\(line.replacingOccurrences(of: "\t", with: " "))\n"
        }
        text += t + "\n"
    }
    try! tsv.write(toFile: args[3], atomically: true, encoding: .utf8)
    let t0 = Date()
    let out = FilterListConverter.convert(text)
    let ms = Date().timeIntervalSince(t0) * 1000
    try! out.rules.encodedJSON().write(toFile: args[2], atomically: true, encoding: .utf8)
    print("kaizu rules=\(out.rules.count) skipped=\(out.skipped) convert_ms=\(Int(ms))")

case "compile":
    // compile rules.json  (isolated store in temp dir)
    let json = try! String(contentsOfFile: args[2], encoding: .utf8)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kaizu-harness-store-\(UUID().uuidString)")
    let store = WKContentRuleListStore(url: dir)!
    let t0 = Date()
    store.compileContentRuleList(forIdentifier: "t", encodedContentRuleList: json) { list, error in
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        if let error { print("FAIL \(ms)ms \(error)") } else { print("OK \(ms)ms") }
        try? FileManager.default.removeItem(at: dir)
        exit(error == nil ? 0 : 2)
    }
    RunLoop.main.run()

case "probe":
    // probe rules.json url seconds : load url in a WKWebView with the rules applied
    let json = try! String(contentsOfFile: args[2], encoding: .utf8)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kaizu-harness-store-\(UUID().uuidString)")
    let store = WKContentRuleListStore(url: dir)!
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let secs = Double(args[4]) ?? 5
    var web: WKWebView?
    store.compileContentRuleList(forIdentifier: "t", encodedContentRuleList: json) { list, error in
        guard let list else { print("compile FAIL \(String(describing: error))"); exit(2) }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        cfg.userContentController.add(list)
        let w = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: cfg)
        web = w
        w.load(URLRequest(url: URL(string: args[3])!))
        DispatchQueue.main.asyncAfter(deadline: .now() + secs) {
            try? FileManager.default.removeItem(at: dir)
            exit(0)
        }
    }
    RunLoop.main.run()
    _ = web

case "match":
    // match requests.tsv rules1.json [rules2.json ...] -> per request: block/allow \t rule
    let reqs = try! String(contentsOfFile: args[2], encoding: .utf8).split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    let sets = args[3...].map { loadRules($0) }
    var results = [String](repeating: "", count: reqs.count)
    let lock = NSLock()
    DispatchQueue.concurrentPerform(iterations: reqs.count) { i in
        let q = reqs[i]
        var blocked = false
        var by = ""
        for set in sets {
            let (b, w) = decide(set, url: q[0], top: q[1], abpType: q[2])
            if b { blocked = true; by = by.isEmpty ? w : by }
        }
        lock.lock(); results[i] = (blocked ? "block" : "allow") + "\t" + by; lock.unlock()
    }
    print(results.joined(separator: "\n"))

default: fail("unknown")
}
