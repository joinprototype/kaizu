import SwiftUI
import WebKit

/// The selected tab's page as a rounded card, or its split, plus the peek
/// and find overlays. A lone page is a split of one, so opening or closing
/// a split keeps the page where it is and only its width moves.
struct ContentArea: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let space: Space

    var body: some View {
        Group {
            if let tab = space.selectedTab {
                let split = space.splitTabs
                SplitContent(space: space, panes: split.contains(tab) ? split : [tab], focused: tab)
            } else {
                EmptyState()
                    .pageCard()
            }
        }
        // The scrim fades and the card scales, each on its own.
        .overlay {
            if store.peek != nil, !store.isPeekExpanding {
                Surface.scrim(scheme)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { store.closePeek() }
                    .transition(.opacity)
            }
        }
        .overlay {
            if let peek = store.peek {
                PeekOverlay(tab: peek)
                    .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topTrailing) {
            if store.find != nil {
                FindBar()
                    .padding(12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

/// A tab's live page with its loading bar.
struct PageView: View {
    let tab: BrowserTab
    let accent: Color
    /// Set where a sidebar tab dropped on the page should split with it.
    var splitDrop: SplitDrop?
    /// The half of the page a sidebar tab is being dragged over.
    @State private var dropEdge: HorizontalEdge?

    var body: some View {
        ZStack(alignment: .top) {
            // A closed tab fading out with its card keeps its place, empty,
            // rather than being given a new page.
            if !tab.isDiscarded {
                WebContainer(webView: tab.webView, tabDrop: splitDrop.map { drop in
                    WebContainerView.TabDrop(accepts: drop.accepts, perform: drop.perform) { edge in
                        withAnimation(Motion.snap) { dropEdge = edge }
                    }
                })
            }
            LoadingBar(isLoading: tab.isLoading, progress: tab.progress, color: accent)
                .id(tab.id)
        }
        .overlay {
            if let dropEdge {
                SplitDropPreview(edge: dropEdge, accent: accent)
            }
        }
    }
}

/// Lets a page take a tab dragged from the sidebar: dropped on one half,
/// it opens in split view on that side.
struct SplitDrop {
    var accepts: (UUID) -> Bool
    var perform: (UUID, HorizontalEdge) -> Void
}

/// The half of the page a dragged tab will take.
private struct SplitDropPreview: View {
    let edge: HorizontalEdge
    let accent: Color

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.opacity(0.10))
                .strokeBorder(accent.opacity(0.55), lineWidth: 1.5)
                .frame(width: geometry.size.width / 2)
                .frame(maxWidth: .infinity, alignment: edge == .leading ? .leading : .trailing)
                .animation(Motion.snap, value: edge)
        }
        .padding(6)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

extension View {
    /// The rounded card web pages sit in, everywhere a page is shown.
    func pageCard(cornerRadius: CGFloat = 10, shadow: Bool = true) -> some View {
        background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(shadow ? 0.12 : 0), radius: 2, y: 1)
    }
}

/// Hosts whichever WKWebView is current; swapping tabs swaps the subview,
/// so each page keeps its state while in the background.
struct WebContainer: NSViewRepresentable {
    let webView: WKWebView
    var tabDrop: WebContainerView.TabDrop?

    func makeNSView(context: Context) -> WebContainerView {
        let view = WebContainerView()
        view.host(webView)
        view.tabDrop = tabDrop
        return view
    }

    func updateNSView(_ view: WebContainerView, context: Context) {
        view.host(webView)
        view.tabDrop = tabDrop
    }
}

final class WebContainerView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        dropCatcher.autoresizingMask = [.width, .height]
        addSubview(dropCatcher)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// WKWebView re-sends key events the page didn't consume (e.g. Enter on
    /// Google's sign-in, handled in JS without preventDefault) up the responder
    /// chain. If they reach the window, AppKit plays the alert sound — stop them here.
    override func keyDown(with event: NSEvent) {}

    /// Don't rely on autoresizing alone: a web view hosted while the container
    /// was still zero-sized (e.g. during window restoration) can lag behind.
    override func layout() {
        super.layout()
        for subview in subviews where subview.frame != bounds {
            subview.frame = bounds
        }
    }

    // MARK: - Tabs dropped on the page

    struct TabDrop {
        var accepts: (UUID) -> Bool
        var perform: (UUID, HorizontalEdge) -> Void
        /// The half of the page the tab is over; nil once it leaves or drops.
        var hover: (HorizontalEdge?) -> Void
    }

    /// Set where a dropped sidebar tab should split the page.
    var tabDrop: TabDrop? {
        get { dropCatcher.tabDrop }
        set { dropCatcher.tabDrop = newValue }
    }

    private let dropCatcher = TabDropCatcher()

    func host(_ webView: WKWebView) {
        guard webView.superview !== self else { return }
        subviews.filter { $0 !== dropCatcher }.forEach { $0.removeFromSuperview() }
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        addSubview(webView, positioned: .below, relativeTo: dropCatcher)
        if let window, !(window.firstResponder is NSTextView) {
            window.makeFirstResponder(webView)
        }
    }
}

/// A clear layer over the page that takes sidebar tab drags and nothing
/// else. WKWebView claims every drag over its frame, whatever its type, so
/// only a view on top of it gets the chance; this one registers just for
/// tabs and lets clicks through. Where the page doesn't split (peek, little
/// windows) it still takes tab drags, and refuses them, so the page never
/// receives one.
private final class TabDropCatcher: NSView {
    var tabDrop: WebContainerView.TabDrop?
    private var draggedTab: UUID?
    private var dropEdge: HorizontalEdge?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.kaizuTab])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggedTab = TabDrag(sender.draggingPasteboard).map(\.id).flatMap { tabDrop?.accepts($0) == true ? $0 : nil }
        return draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard draggedTab != nil else { return [] }
        setDropEdge(convert(sender.draggingLocation, from: nil).x < bounds.midX ? .leading : .trailing)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDropEdge(nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let draggedTab, let dropEdge, let tabDrop else { return false }
        setDropEdge(nil)
        tabDrop.perform(draggedTab, dropEdge)
        return true
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        setDropEdge(nil)
        draggedTab = nil
    }

    private func setDropEdge(_ edge: HorizontalEdge?) {
        guard edge != dropEdge else { return }
        dropEdge = edge
        tabDrop?.hover(edge)
    }
}

/// Glides with the page's progress and never runs backwards (redirects
/// restart WebKit's count); when the page is in, it reaches the end, then
/// fades.
struct LoadingBar: View {
    let isLoading: Bool
    let progress: Double
    let color: Color
    @State private var shown = 0.0
    @State private var isVisible = false
    /// Which load the bar is showing, so a finish can't hide the next one.
    @State private var load = 0

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(color)
                .frame(width: max(proxy.size.width * shown, 24), height: 3)
        }
        .frame(height: 3)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(false)
        .onAppear {
            if isLoading { start() }
        }
        .onChange(of: isLoading) { _, loading in
            loading ? start() : finish()
        }
        .onChange(of: progress) { _, progress in
            guard isLoading, progress > shown else { return }
            withAnimation(.easeOut(duration: 0.25)) { shown = progress }
        }
    }

    private func start() {
        load += 1
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            shown = progress
            isVisible = true
        }
    }

    private func finish() {
        guard isVisible else { return }
        let finishing = load
        withAnimation(.easeOut(duration: 0.2)) {
            shown = 1
        } completion: {
            guard load == finishing else { return }
            withAnimation(.easeOut(duration: 0.25)) { isVisible = false }
        }
    }
}
