import WebKit

/// Tells a tab when any audio or video in it (iframes included) plays, stops
/// or changes volume, so the sidebar's speaker and mini player stay current
/// without polling every tab, and mutes media for the tab's mute button (only
/// elements it muted itself are unmuted again). Runs in an isolated world,
/// invisible to pages. The script is one of the content blocker's standard
/// scripts; each tab adds its own message handler.
package final class MediaEvents: NSObject, WKScriptMessageHandler {
    private static let name = "kaizuMedia"
    package static let script = WKUserScript(
        source: """
        (() => {
          let muted = false;
          const ours = new WeakSet();
          const mute = (media) => {
            if (muted && !media.muted) { media.muted = true; ours.add(media); }
          };
          const post = () => window.webkit?.messageHandlers?.\(name)?.postMessage(0);
          for (const type of ['play', 'pause', 'ended', 'emptied', 'volumechange']) {
            document.addEventListener(type, (event) => {
              if (type === 'play') mute(event.target);
              post();
            }, true);
          }
          window.kaizuSetMuted = (value) => {
            muted = value;
            for (const media of document.querySelectorAll('video, audio')) {
              if (value) mute(media);
              else if (ours.has(media)) { media.muted = false; ours.delete(media); }
            }
          };
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false,
        in: .defaultClient
    )

    private weak var listener: (any MediaEventsListener)?

    package static func install(on controller: WKUserContentController, for listener: any MediaEventsListener) {
        let events = MediaEvents()
        events.listener = listener
        controller.add(events, contentWorld: .defaultClient, name: name)
    }

    package func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        listener?.mediaDidChange(in: message.frameInfo)
    }
}

/// What hears a page's media play, stop and change volume: its tab.
package protocol MediaEventsListener: AnyObject {
    func mediaDidChange(in frame: WKFrameInfo)
}
