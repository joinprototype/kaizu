#if DEBUG
import AppKit
import BrowserCore
import WebKit

extension DebugHooks {
    /// What counts as playing, for the speaker and for hibernation: sound does,
    /// a muted video doesn't. The samples are silent: WebKit goes by whether
    /// a page could be heard, so nothing comes out of the speakers.
    static func qaAudible(_ store: BrowserStore) {
        var passed = 0, failed = 0
        func check(_ label: String, _ condition: Bool) {
            if condition { passed += 1 } else { failed += 1 }
            log("QA audible \(condition ? "ok" : "FAILED"): \(label)")
        }
        let silence = """
        window.qaSilence = () => {
          const rate = 8000, count = rate * 60;
          const buffer = new ArrayBuffer(44 + count * 2), view = new DataView(buffer);
          const text = (at, string) => [...string].forEach((c, i) => view.setUint8(at + i, c.charCodeAt(0)));
          text(0, 'RIFF'); view.setUint32(4, 36 + count * 2, true); text(8, 'WAVEfmt ');
          view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true);
          view.setUint32(24, rate, true); view.setUint32(28, rate * 2, true);
          view.setUint16(32, 2, true); view.setUint16(34, 16, true);
          text(36, 'data'); view.setUint32(40, count * 2, true);
          return URL.createObjectURL(new Blob([buffer], { type: 'audio/wav' }));
        };
        """
        func page() async -> BrowserTab {
            let tab = store.openTab(URL(string: "https://example.com/"))
            store.select(tab)
            for _ in 0..<100 {
                try? await Task.sleep(for: .milliseconds(100))
                if tab.isLoaded, !tab.isLoading, tab.webView.url != nil { break }
            }
            _ = try? await tab.webView.evaluateJavaScript(silence + "0")
            return tab
        }
        func run(_ tab: BrowserTab, _ script: String) async {
            _ = try? await tab.webView.evaluateJavaScript(script + ";0")
            try? await Task.sleep(for: .seconds(1))
        }
        Task {
            let other = store.openTab(URL(string: "about:blank"))
            let video = await page()
            await run(video, """
            window.qaAudio = document.body.appendChild(document.createElement('audio'));
            qaAudio.src = qaSilence(); qaAudio.loop = true; qaAudio.muted = true; qaAudio.play()
            """)
            check("WebKit calls a muted element playing", await video.webView.requestMediaPlaybackState() == .playing)
            await video.refreshMediaState()
            check("but the tab isn't", !video.isPlayingMedia)
            check("and isn't busy", await !video.isBusy)

            await run(video, "qaAudio.muted = false")
            check("unmuting by the page counts, with no re-check", video.isPlayingMedia)
            check("and it's busy", await video.isBusy)

            video.toggleMute()
            try? await Task.sleep(for: .seconds(1))
            check("a tab you muted still counts as playing", video.isPlayingMedia)
            check("and stays busy", await video.isBusy)
            video.toggleMute()
            try? await Task.sleep(for: .seconds(1))

            store.select(other)
            try? await Task.sleep(for: .seconds(1))
            await store.app.hibernateIdleTabs(olderThan: 0)
            check("sound keeps a background tab from hibernating", video.isLoaded)

            await run(video, "qaAudio.muted = true")
            check("muting by the page stops it counting", !video.isPlayingMedia)
            await store.app.hibernateIdleTabs(olderThan: 0)
            check("a silent background tab hibernates", !video.isLoaded)

            let detached = await page()
            await run(detached, "window.qaDetached = new Audio(qaSilence()); qaDetached.loop = true; qaDetached.play()")
            store.select(other)
            try? await Task.sleep(for: .seconds(1))
            check("sound from an element not in the page is busy", await detached.isBusy)
            await store.app.hibernateIdleTabs(olderThan: 0)
            check("and isn't hibernated", detached.isLoaded)

            let synth = await page()
            await run(synth, """
            window.qaContext = new AudioContext(); const gain = qaContext.createGain(); gain.gain.value = 0.00001;
            const tone = qaContext.createOscillator(); tone.connect(gain); gain.connect(qaContext.destination); tone.start(); qaContext.resume()
            """)
            store.select(other)
            try? await Task.sleep(for: .seconds(1))
            check("Web Audio is busy", await synth.isBusy)

            log("QA audible done: \(passed) ok, \(failed) failed")
            NSApp.terminate(nil)
        }
    }
}
#endif
