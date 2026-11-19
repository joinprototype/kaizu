import WebKit

extension BrowserTab {
    /// Media in `frame` started or stopped (from `MediaEvents`).
    func mediaDidChange(in frame: WKFrameInfo) {
        if !frame.isMainFrame {
            mediaFrames = Array((mediaFrames + [frame]).suffix(8))
        }
        if isMuted {
            applyMute(in: frame)
        }
        Task {
            // Let the page's player settle (a pause can briefly still report playing).
            try? await Task.sleep(for: .milliseconds(300))
            await refreshMediaState()
        }
    }

    /// Floats the page's main playing video (audible, the largest) in picture
    /// in picture. Scripts the app runs count as a user gesture, which the
    /// Picture-in-Picture API requires. Call before switching away, while
    /// the page is still on screen: the script is sent right away.
    func enterPictureInPicture() {
        let script = """
        (() => {
          if (document.pictureInPictureElement) return false;
          const video = [...document.querySelectorAll('video')]
            .filter((v) => !v.paused && !v.ended && !v.muted && v.readyState > 2)
            .sort((a, b) => b.clientWidth * b.clientHeight - a.clientWidth * a.clientHeight)[0];
          if (!video) return false;
          if (video.webkitSupportsPresentationMode?.('picture-in-picture')) {
            video.webkitSetPresentationMode('picture-in-picture');
          } else {
            video.requestPictureInPicture();
          }
          return true;
        })()
        """
        _webView?.evaluateJavaScript(script, in: nil, in: .defaultClient) { [weak self] result in
            self?.isInAutoPictureInPicture = (try? result.get()) as? Bool == true
        }
    }

    /// Puts a video floated by `enterPictureInPicture` back in its page.
    func exitPictureInPicture() {
        guard isInAutoPictureInPicture else { return }
        isInAutoPictureInPicture = false
        let script = """
        (() => {
          const video = document.pictureInPictureElement;
          if (!video) return;
          if (video.webkitPresentationMode === 'picture-in-picture') video.webkitSetPresentationMode('inline');
          else document.exitPictureInPicture();
        })()
        """
        _webView?.evaluateJavaScript(script, in: nil, in: .defaultClient)
    }

    func toggleMute() {
        isMuted.toggle()
        applyMute(in: nil)
        mediaFrames.forEach { applyMute(in: $0) }
    }

    func applyMute(in frame: WKFrameInfo?) {
        _webView?.evaluateJavaScript("window.kaizuSetMuted?.(\(isMuted))", in: frame, in: .defaultClient)
    }

    func refreshMediaState() async {
        guard let _webView else { return }
        let playing = await isPlayingSound(in: _webView)
        if playing != isPlayingMedia { isPlayingMedia = playing }
    }

    /// Sound, or what would be if you hadn't muted the tab. WebKit calls a
    /// silent video playing too, and pages autoplay those: NYT, YouTube and
    /// Amazon's home pages kept half of ten tabs' memory from hibernating.
    private func isPlayingSound(in webView: WKWebView) async -> Bool {
        await webView.requestMediaPlaybackState() == .playing && (isMuted || webView.isAudible)
    }

    func pauseMedia() {
        _webView?.pauseAllMediaPlayback(completionHandler: nil)
        isPlayingMedia = false
    }

    /// A muted capture session can resume. Reading this must not wake an unloaded tab.
    var isCapturingMedia: Bool {
        guard let _webView else { return false }
        return _webView.cameraCaptureState != .none || _webView.microphoneCaptureState != .none
    }

    /// Whether the page is playing sound or using the camera/microphone,
    /// so it must not be hibernated.
    var isBusy: Bool {
        get async {
            guard let _webView else { return false }
            if isCapturingMedia { return true }
            return await isPlayingSound(in: _webView)
        }
    }
}

private extension WKWebView {
    /// WebKit's own answer to whether the page can be heard. It has no public
    /// name, so without it a tab goes by the playback state alone.
    var isAudible: Bool {
        let key = "_isPlayingAudio"
        return responds(to: NSSelectorFromString(key)) ? value(forKey: key) as? Bool ?? true : true
    }
}
