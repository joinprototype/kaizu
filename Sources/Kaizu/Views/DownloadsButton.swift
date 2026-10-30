import AppKit
import SwiftUI

/// Sidebar button (with a progress ring while downloading) that opens the downloads list.
struct DownloadsButton: View {
    @Environment(\.colorScheme) private var scheme
    @State private var isShowingList = false
    private let downloads = DownloadManager.shared

    var body: some View {
        IconButton(systemName: "arrow.down.circle", help: "Downloads") { isShowingList.toggle() }
            .overlay {
                if let progress = downloads.activeProgress {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.primary.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 22, height: 22)
                        .allowsHitTesting(false)
                        .animation(Motion.snap, value: progress)
                        .transition(.opacity)
                }
            }
            .animation(Motion.snap, value: downloads.activeProgress == nil)
            .popover(isPresented: $isShowingList, arrowEdge: .top) {
                DownloadsList()
            }
    }
}

private struct DownloadsList: View {
    private let downloads = DownloadManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Downloads").font(.headline)
                Spacer()
                Button("Clear") { downloads.clearFinished() }
                    .buttonStyle(.borderless)
                    .disabled(downloads.items.allSatisfy { $0.state == .downloading })
            }
            .padding(12)
            Divider()
            if downloads.items.isEmpty {
                Text("Nothing downloaded yet.")
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
            ForEach(downloads.items) { item in
                DownloadRow(item: item)
                Divider().padding(.leading, 52)
            }
        }
        .frame(width: 320)
    }
}

private struct DownloadRow: View {
    let item: DownloadManager.Item

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(for: .init(filenameExtension: item.destination.pathExtension) ?? .data))
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)
                switch item.state {
                case .downloading:
                    ProgressView(value: item.progress)
                        .controlSize(.small)
                case .finished:
                    Text("Finished").font(.caption).foregroundStyle(.secondary)
                case .failed:
                    Text("Failed").font(.caption).foregroundStyle(.red)
                }
            }
            Spacer(minLength: 4)
            if item.state == .finished {
                Button {
                    DownloadManager.shared.reveal(item)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if item.state == .finished { DownloadManager.shared.open(item) }
        }
    }
}
