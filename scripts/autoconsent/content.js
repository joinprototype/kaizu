// Kaizu's side of autoconsent v2, bundled with @duckduckgo/autoconsent's
// library into Resources/Scripts/autoconsent-isolated.js by
// scripts/vendor-autoconsent.sh. It runs in WebKit's isolated client world in
// every frame, so the page can neither see it nor reach the message handler.
//
// Only two messages cross to the app: `init`, answered with the rules for this
// frame's address, and `eval`, which names one of autoconsent's own snippets
// by id. The snippet's source is left behind on purpose: the app runs its own
// copy of that snippet in the page's world and returns a boolean.
import AutoConsent from './package/dist/autoconsent.esm.js';

(() => {
    const handler = window.webkit?.messageHandlers?.kaizuAutoconsent;
    if (!handler || window.kaizuAutoconsent) return;
    // What autoconsent did here, for debug builds to read from this world.
    const messages = [];
    const consent = new AutoConsent((message) => {
        if (message.type === 'init') {
            return handler.postMessage({ type: 'init', url: message.url }).then((reply) => {
                if (reply) consent.receiveMessageCallback(JSON.parse(reply));
            }, () => {});
        }
        if (message.type === 'eval') {
            return handler.postMessage({ type: 'eval', id: message.id, snippetId: message.snippetId }).then(
                (reply) => consent.receiveMessageCallback(reply),
                () => consent.receiveMessageCallback({ type: 'evalResp', id: message.id, result: false }),
            );
        }
        if (message.type !== 'report') messages.push(message);
    });
    window.kaizuAutoconsent = { messages };
})();
