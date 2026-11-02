import BrowserCore
import SwiftUI
import WebKit

/// The selected tab's page as a rounded card, or its split, plus the peek
/// and find overlays. A lone page is a split of one, so opening or closing
/// a split keeps the page where it is and only its size moves.
struct ContentArea: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let space: Space

    var body: some View {
        Group {
            if let tab = store.selectedTab(in: space) {
                SplitContent(space: space, panes: space.panes(with: tab), focused: tab)
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
                    .transition(Motion.dissolving(.scale(scale: 0.97).combined(with: .opacity)))
            }
        }
        .overlay(alignment: .topTrailing) {
            if store.find != nil {
                FindBar()
                    .padding(12)
                    .transition(Motion.dissolving(.move(edge: .top).combined(with: .opacity)))
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

    var body: some View {
        ZStack(alignment: .top) {
            // A closed tab fading out with its card keeps its place, empty,
            // rather than being given a new page.
            if !tab.isDiscarded {
                WebContainer(webView: tab.webView, tabDrop: splitDrop)
            }
            LoadingBar(isLoading: tab.isLoading, progress: tab.progress, color: accent)
                .id(tab.id)
        }
    }
}

/// Lets a page take a tab dragged from the sidebar: dropped on one side, it
/// opens in split view there.
struct SplitDrop {
    var accepts: (UUID) -> Bool
    /// Where a tab at a point on the page, from its top left, would land.
    var place: (CGPoint) -> SplitPlace
    var perform: (UUID, SplitPlace) -> Void
    /// Where the tab would land; nil once it leaves or drops.
    var hover: ((tab: UUID, place: SplitPlace)?) -> Void
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
    var tabDrop: SplitDrop?

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

    /// Set where a dropped sidebar tab should split the page.
    var tabDrop: SplitDrop? {
        get { dropCatcher.tabDrop }
        set { dropCatcher.tabDrop = newValue }
    }

    private let dropCatcher = TabDropCatcher()

    #if DEBUG
    /// What takes drags here, for QA to hand one.
    var dropTarget: NSView { dropCatcher }
    #endif

    /// The page it was last told to show. Told again, it does nothing: on
    /// its way out it hears once more, after another window has taken the page.
    private weak var hosted: WKWebView?

    func host(_ webView: WKWebView) {
        guard webView !== hosted else { return }
        hosted = webView
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
    var tabDrop: SplitDrop?
    private var draggedTab: UUID?
    private var dropPlace: SplitPlace?

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
        let point = convert(sender.draggingLocation, from: nil)
        setDropPlace(tabDrop?.place(CGPoint(x: point.x, y: bounds.maxY - point.y)))
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDropPlace(nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let draggedTab, let dropPlace, let tabDrop else { return false }
        setDropPlace(nil)
        tabDrop.perform(draggedTab, dropPlace)
        return true
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        setDropPlace(nil)
        draggedTab = nil
    }

    private func setDropPlace(_ place: SplitPlace?) {
        guard place != dropPlace else { return }
        dropPlace = place
        tabDrop?.hover(place.flatMap { place in draggedTab.map { ($0, place) } })
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
