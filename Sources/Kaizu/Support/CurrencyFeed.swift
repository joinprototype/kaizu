import BrowserCore
import Foundation

/// Exchange rates for currency answers in the command bar. Fetched from the
/// European Central Bank only once someone types a conversion, then cached
/// for half a day (the ECB publishes once per working day).
@MainActor @Observable
final class CurrencyFeed {
    static let shared = CurrencyFeed()
    private static let source = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
    private static let maxAge: TimeInterval = 12 * 60 * 60

    private(set) var rates: CurrencyRates?
    @ObservationIgnored private var fetchedAt: Date?
    @ObservationIgnored private var task: Task<Void, Never>?

    private var file: URL { AppPaths.support.appending(path: "eurofxref.xml") }

    /// Loads the cached copy at once and refreshes it when stale.
    func requestIfNeeded() {
        if rates == nil, let data = try? Data(contentsOf: file) {
            rates = CurrencyRates(ecbXML: data)
            fetchedAt = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        guard task == nil, Date().timeIntervalSince(fetchedAt ?? .distantPast) > Self.maxAge else { return }
        task = Task {
            defer { task = nil }
            guard let (data, response) = try? await URLSession(configuration: .ephemeral).data(from: Self.source),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let fresh = CurrencyRates(ecbXML: data)
            else { return }
            try? data.write(to: file, options: .atomic)
            rates = fresh
            fetchedAt = Date()
        }
    }
}
