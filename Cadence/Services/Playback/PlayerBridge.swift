import Foundation

/// The JavaScript side of the embedded YouTube IFrame player and the messages it sends back.
nonisolated enum PlayerBridge {
    static let messageHandlerName = "player"

    enum Event: String {
        case ready
        case state
        case progress
        case error
        case apiLoadFailed
        /// The lock screen, Control Center or the Mac's Now Playing asked for another song.
        case previousTrack
        case nextTrack
    }

    /// `YT.PlayerState` values.
    enum State: Int {
        case unstarted = -1
        case ended = 0
        case playing = 1
        case paused = 2
        case buffering = 3
        case cued = 5
    }

    enum Message {
        case ready
        case stateChange(State)
        case progress(current: TimeInterval, duration: TimeInterval)
        case error(code: Int)
        case apiLoadFailed
        case previousTrack
        case nextTrack

        init?(body: Any) {
            guard let dictionary = body as? [String: Any],
                  let name = dictionary["event"] as? String,
                  let event = Event(rawValue: name)
            else { return nil }
            let data = dictionary["data"]
            switch event {
            case .ready:
                self = .ready
            case .state:
                guard let raw = (data as? NSNumber)?.intValue, let state = State(rawValue: raw) else { return nil }
                self = .stateChange(state)
            case .progress:
                guard let values = data as? [String: Any],
                      let current = (values["current"] as? NSNumber)?.doubleValue,
                      let duration = (values["duration"] as? NSNumber)?.doubleValue
                else { return nil }
                self = .progress(current: current, duration: duration)
            case .error:
                guard let code = (data as? NSNumber)?.intValue else { return nil }
                self = .error(code: code)
            case .apiLoadFailed:
                self = .apiLoadFailed
            case .previousTrack:
                self = .previousTrack
            case .nextTrack:
                self = .nextTrack
            }
        }
    }

    // MARK: Commands

    static let play = "player.playVideo();"

    /// Stops the page (and YouTube's player inside it) from learning it was hidden, so it doesn't
    /// pause itself when the app goes to the background. Used by the unofficial background play.
    static let keepPageVisibleScript = """
    Object.defineProperty(document, 'hidden', { get: function () { return false; } });
    Object.defineProperty(document, 'visibilityState', { get: function () { return 'visible'; } });
    document.addEventListener('visibilitychange', function (event) { event.stopImmediatePropagation(); }, true);
    """
    /// The system's media controls (lock screen, Control Center, the Mac's Now Playing) show what
    /// the playing page's media session offers, and YouTube's player offers 10-second skips. Runs
    /// in every frame, so it reaches YouTube's player too, before YouTube's own scripts: it offers
    /// previous and next song instead, like Apple Music, and keeps YouTube from putting the skips back.
    static let systemMediaControlsScript = """
    (function () {
      var session = navigator.mediaSession;
      var handlers = window.webkit && window.webkit.messageHandlers;
      if (!session || !handlers || !handlers.\(messageHandlerName)) { return; }
      function post(event) { handlers.\(messageHandlerName).postMessage({ event: event, data: null }); }
      var ours = {
        previoustrack: function () { post('\(Event.previousTrack.rawValue)'); },
        nexttrack: function () { post('\(Event.nextTrack.rawValue)'); },
        seekbackward: null,
        seekforward: null
      };
      var setActionHandler = session.setActionHandler.bind(session);
      session.setActionHandler = function (action, handler) {
        if (Object.prototype.hasOwnProperty.call(ours, action)) { return; }
        setActionHandler(action, handler);
      };
      Object.keys(ours).forEach(function (action) {
        try { setActionHandler(action, ours[action]); } catch (error) {}
      });
    })();
    """
    static let pause = "player.pauseVideo();"

    /// Stops YouTube's video from rendering while background play shows artwork instead; the
    /// sound carries on. On a real device this shortens the sound's dip as the app leaves and
    /// returns to the screen.
    static func setVideoHidden(_ hidden: Bool) -> String {
        "setVideoHidden(\(hidden));"
    }

    /// YouTube's volume runs from 0 to 100.
    private static let volumeScale: Double = 100

    /// `volume` is from 0 to 1.
    static func setVolume(_ volume: Double) -> String {
        "player.setVolume(\(Int((volume * volumeScale).rounded())));"
    }

    static func seek(to seconds: TimeInterval) -> String {
        "player.seekTo(\(seconds), true);"
    }

    /// `videoID` must pass `isValidVideoID` first; it is inserted into JavaScript.
    static func load(videoID: String, autoplay: Bool, startingAt seconds: TimeInterval = 0) -> String {
        let function = autoplay ? "loadVideoById" : "cueVideoById"
        return "player.\(function)({ videoId: '\(videoID)', startSeconds: \(seconds) });"
    }

    private static let videoIDCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    )

    static func isValidVideoID(_ videoID: String) -> Bool {
        !videoID.isEmpty && videoID.unicodeScalars.allSatisfy(videoIDCharacters.contains)
    }

    // MARK: Page

    private static let millisecondsPerSecond: TimeInterval = 1_000

    /// Hosts the official player with YouTube's own controls hidden; the app draws native ones.
    static func html(origin: URL?) -> String {
        let origin = origin?.absoluteString ?? ""
        let progressInterval = Int(PlaybackPolicy.progressInterval * millisecondsPerSecond)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>
          html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: #000; overflow: hidden; }
          #player { position: absolute; top: 0; left: 0; width: 100%; height: 100%; }
        </style>
        </head>
        <body>
        <div id="player"></div>
        <script>
          var player = null;
          var progressTimer = null;

          function post(event, data) {
            window.webkit.messageHandlers.\(messageHandlerName).postMessage({ event: event, data: data });
          }

          function postProgress() {
            if (!player || !player.getCurrentTime) { return; }
            post('\(Event.progress.rawValue)', {
              current: player.getCurrentTime() || 0,
              duration: player.getDuration() || 0
            });
          }

          function setVideoHidden(hidden) {
            var frame = player && player.getIframe ? player.getIframe() : null;
            if (frame) { frame.style.display = hidden ? 'none' : ''; }
          }

          function setProgressUpdates(enabled) {
            if (progressTimer) { clearInterval(progressTimer); progressTimer = null; }
            if (enabled) { progressTimer = setInterval(postProgress, \(progressInterval)); }
          }

          function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
              width: '100%',
              height: '100%',
              playerVars: {
                playsinline: 1,
                controls: 0,
                rel: 0,
                fs: 0,
                iv_load_policy: 3, // hide video annotations
                origin: '\(origin)',
                widget_referrer: '\(origin)'
              },
              events: {
                onReady: function () { post('\(Event.ready.rawValue)', null); },
                onStateChange: function (event) {
                  setProgressUpdates(event.data === YT.PlayerState.PLAYING);
                  postProgress();
                  post('\(Event.state.rawValue)', event.data);
                },
                onError: function (event) { post('\(Event.error.rawValue)', event.data); }
              }
            });
          }
        </script>
        <script src="\(GoogleEndpoint.iframeAPI.absoluteString)"
                onerror="post('\(Event.apiLoadFailed.rawValue)', null)"></script>
        </body>
        </html>
        """
    }
}
