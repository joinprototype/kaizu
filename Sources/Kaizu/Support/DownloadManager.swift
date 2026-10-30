import AppKit
import WebKit

/// Saves every download straight to ~/Downloads (no prompt, like Safari's
/// default) and keeps a short list for the sidebar's downloads panel.
@MainActor @Observable
final class DownloadManager: NSObject, WKDownloadDelegate {
    static let shared = DownloadManager()
    static let listLimit = 20

    struct Item: Identifiable {
        enum State {
            case downloading, finished, failed
        }

        let id = UUID()
        let destination: URL
        var progress = 0.0
        var state = State.downloading

        var filename: String { destination.lastPathComponent }
    }

    /// Newest first.
    private(set) var items: [Item] = []

    @ObservationIgnored var onFinish: ((String) -> Void)?
    @ObservationIgnored private var active: [ObjectIdentifier: (itemID: UUID, observation: NSKeyValueObservation)] = [:]

    var activeItems: [Item] { items.filter { $0.state == .downloading } }

    /// Overall progress of running downloads, for the sidebar ring.
    var activeProgress: Double? {
        let running = activeItems
        guard !running.isEmpty else { return nil }
        return running.map(\.progress).reduce(0, +) / Double(running.count)
    }

    func reveal(_ item: Item) {
        NSWorkspace.shared.activateFileViewerSelecting([item.destination])
    }

    func open(_ item: Item) {
        NSWorkspace.shared.open(item.destination)
    }

    func clearFinished() {
        items.removeAll { $0.state != .downloading }
    }

    // MARK: - WKDownloadDelegate

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        let item = Item(destination: uniqueDestination(for: (suggestedFilename as NSString).lastPathComponent))
        items.insert(item, at: 0)
        items = Array(items.prefix(Self.listLimit))
        let itemID = item.id
        let observation = download.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                // Publish whole percents only: KVO fires thousands of times per download.
                self?.update(itemID) { if fraction - $0.progress >= 0.01 { $0.progress = fraction } }
            }
        }
        active[ObjectIdentifier(download)] = (itemID, observation)
        completionHandler(item.destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let (itemID, _) = active.removeValue(forKey: ObjectIdentifier(download)) else { return }
        update(itemID) {
            $0.progress = 1
            $0.state = .finished
        }
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        // Makes the Downloads stack in the Dock bounce.
        DistributedNotificationCenter.default().post(
            name: Notification.Name("com.apple.DownloadFileFinished"),
            object: item.destination.path
        )
        onFinish?(item.filename)
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        guard let (itemID, _) = active.removeValue(forKey: ObjectIdentifier(download)) else { return }
        let error = error as NSError
        Log.downloads.error("Download failed: \(error.domain, privacy: .public) \(error.code)")
        update(itemID) { $0.state = .failed }
    }

    private func update(_ id: UUID, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]
        change(&item)
        // Writing an unchanged item would still re-render everything watching `items`.
        if item.progress != items[index].progress || item.state != items[index].state {
            items[index] = item
        }
    }

    private func uniqueDestination(for filename: String) -> URL {
        let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let name = filename.isEmpty ? "download" : filename
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = directory.appending(path: name)
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            counter += 1
            candidate = directory.appending(path: ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)")
        }
        return candidate
    }
}
