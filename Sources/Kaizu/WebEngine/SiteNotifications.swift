import AppKit
@preconcurrency import UserNotifications
import WebKit

/// Lets sites notify you. WebKit's own `Notification` has no public way to
/// deliver anything, so a small script takes its place in the page, and what
/// it's asked to show goes to macOS once this side has checked the site is
/// allowed. The page can't tell macOS anything directly: it talks to a relay
/// in our own content world over DOM events, because a message handler in
/// the page's world would add `window.webkit`, which Safari pages don't have
/// and sign-in pages look for. There's no push service behind this, so a
/// site can only notify while a page of it runs: one tab of each allowed
/// site stays loaded and isn't paused in the background. Private windows get
/// the same script, or pages could spot one, but nothing is read or kept:
/// every site there is one that hasn't been asked.
///
/// macOS refuses this to apps without a developer signature, which until
/// Developer ID means every build of Kaizu. So a notification also waits on
/// its tab, a dot in the sidebar and a count on the Dock, and the Dock icon
/// bounces when macOS wouldn't take it.
@MainActor
final class SiteNotifications: NSObject, WKScriptMessageHandlerWithReply {
    /// Its key in `Settings.sitePermissions`.
    static let permission = "notifications"
    private static let world = WKContentWorld.world(name: "KaizuNotifications")
    private static let handlerName = "kaizuNotifications"
    private static let maximumTitle = 200
    private static let maximumBody = 1000
    #if DEBUG
    /// Tells the QA hook what was handed to macOS.
    static var onDeliver: ((String) -> Void)?
    #endif

    private weak var tab: BrowserTab?
    private var isAsking = false

    /// Main frames only, as in Safari. Part of the content blocker's
    /// standard scripts, which it puts back whenever it replaces them.
    static let scripts = [
        WKUserScript(source: relayScript, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world),
        WKUserScript(source: pageScript, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page),
    ]

    static func install(on controller: WKUserContentController, for tab: BrowserTab) {
        let handler = SiteNotifications()
        handler.tab = tab
        controller.addScriptMessageHandler(handler, contentWorld: world, name: handlerName)
    }

    /// Nil without a bundle, as in development, where asking for it crashes.
    private static var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    /// macOS asks once; after that this reports its answer. Nil when it
    /// won't deal with this build at all, so there's nothing to ask you.
    static func requestDelivery() async -> Bool? {
        try? await center?.requestAuthorization(options: [.alert, .sound])
    }

    /// Fires a notification's event in the page that showed it.
    static func tell(_ tab: BrowserTab, notification id: String, happened type: String) {
        guard tab.isLoaded, let detail = try? JSONEncoder().encode(["id": id, "type": type]) else { return }
        tab.webView.callAsyncJavaScript(
            "window.dispatchEvent(new CustomEvent('kaizu-notification-event', { detail }))",
            arguments: ["detail": String(decoding: detail, as: UTF8.self)],
            in: nil,
            in: world,
            completionHandler: nil
        )
    }

    /// Only a main frame over HTTPS, as in other browsers; anything else
    /// hears nothing. Goes by the frame's own origin: the first question
    /// arrives as the page starts, before the web view reports its address.
    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        let origin = message.frameInfo.securityOrigin
        guard let tab, let settings = tab.app?.settings, let webView = message.webView, message.frameInfo.isMainFrame,
              origin.protocol == "https", !origin.host.isEmpty,
              let body = message.body as? [String: Any], let kind = body["kind"] as? String
        else { return replyHandler(nil, nil) }
        let host = origin.host
        let answer = tab.profile.isPrivate ? nil : settings.sitePermissions[host]?[Self.permission]

        switch kind {
        case "permission":
            replyHandler(Self.state(answer), nil)
        case "request":
            if let answer { return replyHandler(Self.state(answer), nil) }
            guard !tab.profile.isPrivate, !isAsking, let window = webView.window else {
                return replyHandler(Self.state(nil), nil)
            }
            ask(host: host, tab: tab, window: window) { replyHandler(Self.state($0), nil) }
        case "show":
            guard answer == true else { return replyHandler(false, nil) }
            Task {
                tab.noteNotification(deliveredByMacOS: await Self.deliver(body, host: host, tab: tab))
                replyHandler(true, nil)
            }
        case "close":
            guard answer == true else { return replyHandler(false, nil) }
            Self.center?.removeDeliveredNotifications(withIdentifiers: [Self.identifier(body, host: host, tab: tab)])
            replyHandler(true, nil)
        default:
            replyHandler(nil, nil)
        }
    }

    private static func state(_ answer: Bool?) -> String {
        answer.map { $0 ? "granted" : "denied" } ?? "default"
    }

    /// The same tag replaces the site's earlier notification, as in the spec.
    private static func identifier(_ body: [String: Any], host: String, tab: BrowserTab) -> String {
        if let tag = body["tag"] as? String, !tag.isEmpty { return "\(host) \(tag)" }
        return "\(tab.id) \(body["id"] as? String ?? "")"
    }

    /// Asks in the tab's window, and remembers the answer: the question is
    /// only worth asking once.
    private func ask(host: String, tab: BrowserTab, window: NSWindow, completion: @escaping @MainActor (Bool?) -> Void) {
        isAsking = true
        let alert = NSAlert()
        alert.messageText = "Allow “\(host)” to send you notifications?"
        alert.informativeText = "They arrive while the site is open in Kaizu, so it stays loaded in the background. Change this from the lock in the address bar."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don’t Allow")
        // The page may be why you're pressing Return: it shouldn't answer this.
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"
        alert.beginSheetModal(for: window) { [weak self] response in
            self?.isAsking = false
            guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn else { return completion(nil) }
            let allowed = response == .alertFirstButtonReturn
            tab.setNotifications(allowed, for: host)
            completion(allowed)
        }
    }

    private static func deliver(_ body: [String: Any], host: String, tab: BrowserTab) async -> Bool {
        let title = String((body["title"] as? String ?? "").prefix(maximumTitle))
        #if DEBUG
        onDeliver?("\(host): \(title)")
        #endif
        guard let center, await center.notificationSettings().authorizationStatus == .authorized else { return false }
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = host
        content.body = String((body["body"] as? String ?? "").prefix(maximumBody))
        content.threadIdentifier = host
        if body["silent"] as? Bool != true {
            content.sound = .default
        }
        content.userInfo = [
            "tab": tab.id.uuidString, "page": body["id"] as? String ?? "", "url": tab.url?.absoluteString ?? "",
        ]
        if let icon = icon(of: tab) {
            content.attachments = [icon]
        }
        let request = UNNotificationRequest(identifier: identifier(body, host: host, tab: tab), content: content, trigger: nil)
        do {
            try await center.add(request)
            return true
        } catch {
            Log.app.notice("Couldn't deliver a notification: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// macOS takes the file away, so each notification gets its own copy.
    private static func icon(of tab: BrowserTab) -> UNNotificationAttachment? {
        guard let data = tab.favicon?.tiffRepresentation,
              let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
        else { return nil }
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        guard (try? png.write(to: file)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "icon", url: file)
    }

    private static let relayScript = """
    (() => {
      const handler = window.webkit.messageHandlers.\(handlerName);
      window.addEventListener("kaizu-notification-ask", async (event) => {
        let message;
        try { message = JSON.parse(event.detail); } catch { return; }
        // Only from a click or a key press, as in Safari: a question a page
        // puts to everyone on arrival is one people learn to refuse. Checked
        // here, where the page can't forge this event's sender or `navigator`.
        const refused = message.kind === "request" && navigator.userActivation?.isActive !== true;
        const reply = refused ? null : await handler.postMessage(message).catch(() => null);
        const detail = JSON.stringify({ ref: message.ref, reply });
        window.dispatchEvent(new CustomEvent("kaizu-notification-reply", { detail }));
      });
      window.dispatchEvent(new CustomEvent("kaizu-notification-ready"));
    })();
    """

    private static let pageScript = """
    (() => {
      let permission = "default";
      let nextReference = 0;
      let nextID = 0;
      const waiting = new Map();
      const shown = new Map();

      const post = (detail) => window.dispatchEvent(new CustomEvent("kaizu-notification-ask", { detail }));
      const ask = (message) => new Promise((resolve) => {
        const ref = ++nextReference;
        const detail = JSON.stringify({ ...message, ref });
        waiting.set(ref, { detail, resolve });
        post(detail);
      });
      // The two worlds' scripts run in no set order: what was said before
      // the relay was listening gets said again.
      window.addEventListener("kaizu-notification-ready", () => {
        for (const { detail } of waiting.values()) post(detail);
      });
      window.addEventListener("kaizu-notification-reply", (event) => {
        const { ref, reply } = JSON.parse(event.detail);
        waiting.get(ref)?.resolve(reply);
        waiting.delete(ref);
      });
      window.addEventListener("kaizu-notification-event", (event) => {
        const { id, type } = JSON.parse(event.detail);
        shown.get(id)?.(type);
      });
      const ready = ask({ kind: "permission" }).then((state) => { permission = state ?? "default"; });

      class Notification extends EventTarget {
        // Unique across reloads, or a click could reach the wrong page's.
        #id = Date.now().toString(36) + "-" + ++nextID;
        constructor(title, options = {}) {
          if (arguments.length === 0) throw new TypeError("Notification needs a title");
          super();
          Object.assign(this, {
            title: String(title), body: String(options.body ?? ""), tag: String(options.tag ?? ""),
            icon: String(options.icon ?? ""), badge: String(options.badge ?? ""), image: String(options.image ?? ""),
            dir: options.dir ?? "auto", lang: options.lang ?? "", data: options.data ?? null,
            silent: options.silent ?? null, requireInteraction: Boolean(options.requireInteraction),
            timestamp: options.timestamp ?? Date.now(),
            onclick: null, onshow: null, onclose: null, onerror: null,
          });
          const { title: text, body, tag, silent } = this;
          ask({ kind: "show", id: this.#id, title: text, body, tag, silent }).then((delivered) => {
            if (delivered) shown.set(this.#id, (type) => this.#fire(type));
            this.#fire(delivered ? "show" : "error");
          });
        }
        #fire(type) {
          const event = new Event(type, { cancelable: true });
          this["on" + type]?.call(this, event);
          this.dispatchEvent(event);
        }
        close() {
          ask({ kind: "close", id: this.#id, tag: this.tag });
          if (shown.delete(this.#id)) this.#fire("close");
        }
        static get permission() { return permission; }
        static get maxActions() { return 0; }
        static requestPermission(callback) {
          return ask({ kind: "request" }).then((state) => {
            permission = state ?? permission;
            callback?.(permission);
            return permission;
          });
        }
      }
      Object.defineProperty(window, "Notification", { value: Notification, writable: true, configurable: true });

      if (window.ServiceWorkerRegistration) {
        ServiceWorkerRegistration.prototype.showNotification = function (title, options) {
          new Notification(title, options);
          return Promise.resolve();
        };
        ServiceWorkerRegistration.prototype.getNotifications = () => Promise.resolve([]);
      }

      const query = navigator.permissions?.query?.bind(navigator.permissions);
      if (query) {
        navigator.permissions.query = (descriptor) => {
          if (descriptor?.name !== "notifications") return query(descriptor);
          return ready.then(() => Object.assign(new EventTarget(), {
            name: "notifications", state: permission === "default" ? "prompt" : permission, onchange: null,
          }));
        };
      }
    })();
    """
}

extension AppModel {
    /// The Dock's count of notifications you haven't looked at yet.
    func updateDockBadge() {
        let waiting = Set(spaces.flatMap(\.allTabs)).reduce(0) { $0 + $1.unreadNotifications }
        NSApp.dockTile.badgeLabel = waiting > 0 ? String(waiting) : nil
    }
}

/// Answers macOS when a notification is about to show or was clicked.
final class NotificationClicks: NSObject, UNUserNotificationCenterDelegate {
    private let open: @MainActor @Sendable (_ tab: UUID?, _ page: String, _ url: URL?) -> Void

    init(open: @escaping @MainActor @Sendable (UUID?, String, URL?) -> Void) {
        self.open = open
    }

    /// By default macOS keeps quiet while the app is in front.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let tab = (info["tab"] as? String).flatMap(UUID.init(uuidString:))
        let page = info["page"] as? String ?? ""
        let url = (info["url"] as? String).flatMap(URL.init(string:))
        await open(tab, page, url)
    }
}
