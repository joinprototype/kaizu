import WebKit

/// Safari's "Hide Distracting Items" (Arc's zap): while picking, the item
/// under the pointer is outlined and a click fades it away; the site
/// remembers it as a CSS selector and hides it on later visits. The
/// scripts and their message handler live in their own content world, so
/// pages can't call them; the style sheet itself is in the page's DOM,
/// where a page could find it, like any page change an extension makes.
@MainActor
final class HiddenItems: NSObject, WKScriptMessageHandler {
    static let world = WKContentWorld.world(name: "KaizuHiddenItems")
    private static let handlerName = "kaizuHide"
    /// Per site: enough for any real clean-up, not for a page spamming picks.
    static let maximumPerSite = 64
    static let maximumSelectorLength = 400
    private weak var tab: BrowserTab?

    static func install(on controller: WKUserContentController, for tab: BrowserTab) {
        let handler = HiddenItems()
        handler.tab = tab
        controller.add(handler, contentWorld: world, name: handlerName)
    }

    /// A picked item's selector, from the picking script: only while the
    /// user is picking on this tab, from its main frame, and from the page
    /// the tab is on (not one it's just leaving).
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let tab, !tab.profile.isPrivate, let store = tab.store, store.hidingItemsTabID == tab.id,
              message.frameInfo.isMainFrame, let selector = message.body as? String,
              selector.count <= Self.maximumSelectorLength,
              message.frameInfo.securityOrigin.host == tab.url?.host()
        else { return }
        store.settings.hide(selector, on: tab.url)
    }

    /// Hides the site's remembered items; safe to call again (it replaces
    /// its own style sheet). Each rule is added on its own, so one that
    /// doesn't parse can't take the others with it.
    static func apply(_ selectors: [String], in webView: WKWebView) {
        webView.callAsyncJavaScript(
            """
            const apply = () => {
                let style = document.getElementById("kaizu-hidden-items");
                if (!style) {
                    style = document.createElement("style");
                    style.id = "kaizu-hidden-items";
                    (document.head || document.documentElement).appendChild(style);
                }
                const sheet = style.sheet;
                while (sheet.cssRules.length) sheet.deleteRule(0);
                for (const selector of selectors) {
                    try { sheet.insertRule(selector + " { display: none !important; }", sheet.cssRules.length) } catch {}
                }
            };
            if (document.documentElement) apply();
            else document.addEventListener("DOMContentLoaded", apply, { once: true });
            """,
            arguments: ["selectors": selectors],
            in: nil,
            in: world,
            completionHandler: nil
        )
    }

    static func startPicking(in webView: WKWebView) {
        webView.evaluateJavaScript(pickingScript, in: nil, in: world) { _ in }
    }

    static func stopPicking(in webView: WKWebView) {
        webView.evaluateJavaScript("window.__kaizuStopHiding?.(); 0", in: nil, in: world) { _ in }
    }

    #if DEBUG
    /// The QA hook clicks by script; it sets this flag in our world, where
    /// pages can't. Release builds take real events only.
    private static let isReal = "(event.isTrusted || window.__kaizuQA === true)"
    #else
    private static let isReal = "event.isTrusted"
    #endif

    /// A clear shield over the page takes every press, so nothing reaches
    /// the page (frames included); what's under the pointer is found by
    /// looking through the shield. Synthetic events from the page are ignored.
    private static let pickingScript = """
    (() => {
      if (window.__kaizuStopHiding) return 0;
      const shield = document.createElement("div");
      shield.style.cssText = "position:fixed;inset:0;z-index:2147483647;cursor:crosshair;background:transparent";
      const box = document.createElement("div");
      box.style.cssText = "position:fixed;z-index:2147483647;pointer-events:none;display:none;" +
        "border:2px solid rgba(140,58,50,0.9);background:rgba(140,58,50,0.08);border-radius:4px;" +
        "transition:left 80ms ease-out,top 80ms ease-out,width 80ms ease-out,height 80ms ease-out";
      document.documentElement.append(shield, box);
      const under = (x, y) => {
        shield.style.pointerEvents = "none";
        const element = document.elementFromPoint(x, y);
        shield.style.pointerEvents = "auto";
        return !element || element === document.body || element === document.documentElement ? null : element;
      };
      const outline = element => {
        if (!element) { box.style.display = "none"; return; }
        const rect = element.getBoundingClientRect();
        Object.assign(box.style, {
          display: "block", left: rect.left - 2 + "px", top: rect.top - 2 + "px",
          width: rect.width + 4 + "px", height: rect.height + 4 + "px",
        });
      };
      // Ids and classes that look generated (long numbers) change on reload.
      const stable = name => /^[A-Za-z][\\w-]*$/.test(name) && !/\\d{3,}/.test(name);
      // Always anchored (to an id or the body), so it can't match the same
      // kind of item elsewhere on the page.
      const selectorFor = element => {
        const parts = [];
        for (let node = element; node && node.nodeType === 1; node = node.parentElement) {
          if (node === document.body) { parts.unshift("body"); break; }
          if (node.id && stable(node.id)) { parts.unshift("#" + CSS.escape(node.id)); break; }
          let part = node.localName;
          const classes = [...node.classList].filter(stable).slice(0, 2);
          if (classes.length) part += "." + classes.map(name => CSS.escape(name)).join(".");
          const siblings = node.parentElement ? [...node.parentElement.children].filter(child => child.localName === node.localName) : [];
          if (siblings.length > 1) part += ":nth-of-type(" + (siblings.indexOf(node) + 1) + ")";
          parts.unshift(part);
        }
        return parts.join(" > ");
      };
      const move = event => { if (\(isReal)) outline(under(event.clientX, event.clientY)); };
      const scroll = () => { box.style.display = "none"; };
      const swallow = event => { event.preventDefault(); event.stopPropagation(); };
      const click = event => {
        swallow(event);
        if (!\(isReal)) return;
        const element = under(event.clientX, event.clientY);
        if (!element) return;
        box.style.display = "none";
        element.style.transition = "opacity 220ms ease-out, transform 220ms ease-out";
        element.style.opacity = "0";
        element.style.transform = "scale(0.97)";
        setTimeout(() => element.style.setProperty("display", "none", "important"), 230);
        window.webkit.messageHandlers.\(handlerName).postMessage(selectorFor(element));
      };
      const presses = ["mousedown", "mouseup", "pointerdown", "pointerup", "auxclick", "dblclick", "contextmenu"];
      shield.addEventListener("mousemove", move);
      shield.addEventListener("click", click);
      presses.forEach(type => shield.addEventListener(type, swallow));
      window.addEventListener("scroll", scroll, true);
      window.__kaizuStopHiding = () => {
        window.removeEventListener("scroll", scroll, true);
        shield.remove();
        box.remove();
        delete window.__kaizuStopHiding;
      };
      return 0;
    })()
    """
}
