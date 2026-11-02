import Foundation

/// "time in tokyo", "almaty time", "3pm pst in tokyo", "15:30 to london",
/// "10am est". Worked out from macOS's own time zone data; nothing is fetched.
enum TimeZoneAnswer {
    private struct Place {
        var name: String
        var zone: TimeZone
    }

    /// Big places macOS files under a neighbour, by the zone they follow.
    /// Countries only where one zone covers all of them.
    static let knownAs: [String: [String]] = [
        "America/New_York": ["boston", "miami", "atlanta", "philadelphia", "washington", "ottawa", "montreal", "eastern"],
        "America/Chicago": ["dallas", "houston", "austin", "minneapolis", "new orleans", "nashville", "central"],
        "America/Denver": ["salt lake city", "albuquerque", "mountain"],
        "America/Los_Angeles": ["san francisco", "san diego", "san jose", "seattle", "portland", "las vegas", "pacific"],
        "America/Sao_Paulo": ["rio", "rio de janeiro", "brasilia"],
        "America/Argentina/Buenos_Aires": ["argentina"],
        "America/Bogota": ["colombia"],
        "America/Lima": ["peru"],
        "America/Santiago": ["chile"],
        "Europe/London": ["uk", "united kingdom", "britain", "england", "scotland", "wales", "manchester", "edinburgh"],
        "Europe/Dublin": ["ireland"],
        "Europe/Paris": ["france", "lyon", "marseille"],
        "Europe/Berlin": ["germany", "munich", "frankfurt", "hamburg"],
        "Europe/Madrid": ["spain", "barcelona"],
        "Europe/Rome": ["italy", "milan", "florence", "naples"],
        "Europe/Amsterdam": ["netherlands", "rotterdam"],
        "Europe/Brussels": ["belgium"],
        "Europe/Zurich": ["switzerland", "geneva", "bern"],
        "Europe/Vienna": ["austria"],
        "Europe/Stockholm": ["sweden"],
        "Europe/Oslo": ["norway"],
        "Europe/Copenhagen": ["denmark"],
        "Europe/Helsinki": ["finland"],
        "Europe/Warsaw": ["poland", "krakow"],
        "Europe/Lisbon": ["portugal"],
        "Europe/Athens": ["greece"],
        "Europe/Istanbul": ["turkey", "ankara"],
        "Europe/Kyiv": ["ukraine"],
        "Europe/Prague": ["czechia", "czech republic"],
        "Europe/Budapest": ["hungary"],
        "Europe/Bucharest": ["romania"],
        "Europe/Moscow": ["st petersburg", "saint petersburg"],
        "Atlantic/Reykjavik": ["iceland"],
        "Asia/Almaty": ["kazakhstan", "astana", "shymkent", "karaganda"],
        "Asia/Tashkent": ["uzbekistan", "samarkand"],
        "Asia/Yerevan": ["armenia"],
        "Asia/Baku": ["azerbaijan"],
        "Asia/Jerusalem": ["israel", "tel aviv"],
        "Asia/Dubai": ["uae", "abu dhabi"],
        "Asia/Riyadh": ["saudi arabia", "jeddah"],
        "Asia/Qatar": ["doha"],
        "Asia/Karachi": ["pakistan", "lahore", "islamabad"],
        "Asia/Calcutta": ["india", "kolkata", "delhi", "new delhi", "mumbai", "bangalore", "bengaluru", "chennai", "hyderabad"],
        "Asia/Dhaka": ["bangladesh"],
        "Asia/Kathmandu": ["nepal"],
        "Asia/Colombo": ["sri lanka"],
        "Asia/Bangkok": ["thailand"],
        "Asia/Ho_Chi_Minh": ["vietnam", "hanoi", "saigon"],
        "Asia/Manila": ["philippines"],
        "Asia/Shanghai": ["china", "beijing", "shenzhen", "guangzhou"],
        "Asia/Taipei": ["taiwan"],
        "Asia/Seoul": ["korea", "south korea", "busan"],
        "Asia/Tokyo": ["japan", "osaka", "kyoto"],
        "Africa/Cairo": ["egypt"],
        "Africa/Lagos": ["nigeria", "abuja"],
        "Africa/Nairobi": ["kenya"],
        "Africa/Johannesburg": ["south africa", "cape town"],
        "Pacific/Auckland": ["new zealand", "wellington"],
    ]

    /// Short forms macOS doesn't list, on top of its EST, PST, CET and so on.
    static let shorthand = [
        "NYC": "America/New_York", "DC": "America/New_York", "ET": "America/New_York", "CT": "America/Chicago",
        "MT": "America/Denver", "PT": "America/Los_Angeles", "SF": "America/Los_Angeles", "LA": "America/Los_Angeles",
        "AEST": "Australia/Sydney", "AEDT": "Australia/Sydney",
    ]

    /// Zone names that are usually something else: "christmas time" isn't
    /// about Christmas Island, nor "cat time" about Central Africa.
    private static let otherMeanings: Set<String> = [
        "art", "cat", "center", "christmas", "cot", "easter", "eat", "midway", "pet", "reunion", "wake", "wat", "wet", "wit",
    ]

    /// What people call places, for the zone each one follows. Identifiers,
    /// not zones: this is built on the first thing typed in the command bar.
    private static let places: [String: (name: String, identifier: String)] = {
        var places: [String: (name: String, identifier: String)] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            let path = identifier.split(separator: "/")
            guard path.count > 1, !["Antarctica", "Arctic"].contains(path[0]) else { continue }
            let city = path[path.count - 1].replacingOccurrences(of: "_", with: " ")
            places[city.lowercased()] = (city, identifier)
        }
        for (identifier, names) in knownAs {
            for name in names {
                places[name] = (name.count < 4 ? name.uppercased() : name.capitalized, identifier)
            }
        }
        for (name, identifier) in TimeZone.abbreviationDictionary.merging(shorthand, uniquingKeysWith: { _, ours in ours }) {
            places[name.lowercased()] = (name, identifier)
        }
        return places.filter { !otherMeanings.contains($0.key) }
    }()

    static func answer(_ text: String, now: Date, here: TimeZone, locale: Locale) -> QuickAnswer? {
        let input = text.lowercased()
        return timeThere(input, now: now, here: here, locale: locale) ?? converted(input, now: now, here: here, locale: locale)
    }

    /// "time in tokyo", "what time is it in the uk?", "tokyo time".
    private static func timeThere(_ input: String, now: Date, here: TimeZone, locale: Locale) -> QuickAnswer? {
        let asked = /(?:what(?:'s| is)?\s+)?(?:the\s+)?(?:current\s+)?time(?:\s+is\s+it)?\s+(?:in|at)\s+(?:the\s+)?(.+?)\??/
        guard let match = input.wholeMatch(of: asked)?.1 ?? input.wholeMatch(of: /(.+?)\s+time\??/)?.1,
              let place = place(String(match))
        else { return nil }
        return QuickAnswer(
            question: "Time in \(place.name) · \(difference(of: place.zone, from: here, at: now))",
            answer: moment(now, in: place.zone, comparedTo: here, locale: locale)
        )
    }

    /// "3pm pst in tokyo", "15:30 to london" (from here), "10am est" (to here).
    private static func converted(_ input: String, now: Date, here: TimeZone, locale: Locale) -> QuickAnswer? {
        guard let match = input.wholeMatch(of: /(noon|midnight|(\d{1,2})(?::(\d{2}))?\s*(am|pm)?)(?:\s+(.+))?/),
              let rest = match.5.map(String.init),
              let (hour, minute) = clock(match.1, hour: match.2, minute: match.3, meridiem: match.4)
        else { return nil }

        let split = rest.wholeMatch(of: /(?:(.+?)\s+)?(?:in|to)\s+(.+)/)
        let fromWords = split == nil ? rest : split?.1.map(String.init)
        let toWords = split.map { String($0.2) }
        let from = fromWords.flatMap(place), to = toWords.flatMap(place)
        // Words that were given have to mean somewhere.
        guard (from == nil) == (fromWords == nil), (to == nil) == (toWords == nil) else { return nil }

        let source = from?.zone ?? here
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = source
        guard let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return nil }
        let start = time(date, in: source, locale: locale)
        return QuickAnswer(
            question: "\(start) \(from?.name ?? "your time") in \(to?.name ?? "your time")",
            answer: moment(date, in: to?.zone ?? here, comparedTo: source, locale: locale)
        )
    }

    /// A clock reading needs am/pm or minutes: "3 in tokyo" is not a time.
    private static func clock(
        _ text: Substring, hour: Substring?, minute: Substring?, meridiem: Substring?
    ) -> (hour: Int, minute: Int)? {
        if text == "noon" { return (12, 0) }
        if text == "midnight" { return (0, 0) }
        guard let hour = hour.flatMap({ Int($0) }), minute != nil || meridiem != nil else { return nil }
        let minutes = minute.flatMap { Int($0) } ?? 0
        guard minutes < 60 else { return nil }
        guard let meridiem else { return hour < 24 ? (hour, minutes) : nil }
        guard (1...12).contains(hour) else { return nil }
        return (hour % 12 + (meridiem == "pm" ? 12 : 0), minutes)
    }

    private static func place(_ words: String) -> Place? {
        guard let found = places[words.hasSuffix(" time") ? String(words.dropLast(5)) : words],
              let zone = TimeZone(identifier: found.identifier)
        else { return nil }
        return Place(name: found.name, zone: zone)
    }

    private static func difference(of zone: TimeZone, from here: TimeZone, at date: Date) -> String {
        let hours = Double(zone.secondsFromGMT(for: date) - here.secondsFromGMT(for: date)) / 3600
        guard hours != 0 else { return "same as here" }
        return "\(QuickAnswer.format(abs(hours))) \(abs(hours) == 1 ? "hour" : "hours") \(hours > 0 ? "ahead" : "behind")"
    }

    /// The time in a zone, with the weekday when it's another day than at `other`.
    private static func moment(_ date: Date, in zone: TimeZone, comparedTo other: TimeZone, locale: Locale) -> String {
        let day = Date.FormatStyle(locale: locale, timeZone: zone).weekday(.abbreviated).format(date)
        let otherDay = Date.FormatStyle(locale: locale, timeZone: other).weekday(.abbreviated).format(date)
        let clock = time(date, in: zone, locale: locale)
        return day == otherDay ? clock : "\(day) \(clock)"
    }

    /// Formatters put a narrow no-break space before PM, which then gets copied.
    private static func time(_ date: Date, in zone: TimeZone, locale: Locale) -> String {
        Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: zone).format(date)
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }
}
