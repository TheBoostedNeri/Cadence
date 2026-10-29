package com.nerijus.cadence.playback

import com.nerijus.cadence.config.GoogleEndpoint
import com.nerijus.cadence.config.PlaybackPolicy
import org.json.JSONObject

/** The JavaScript side of the embedded YouTube IFrame player and the messages it sends back.
 *  The same page as the iPhone app's PlayerBridge, posting through a JavaScript interface. */
object PlayerBridge {
    /** The name the page calls the app by: `CadencePlayer.post(json)`. */
    const val INTERFACE_NAME = "CadencePlayer"

    private object Event {
        const val READY = "ready"
        const val STATE = "state"
        const val PROGRESS = "progress"
        const val ERROR = "error"
        const val API_LOAD_FAILED = "apiLoadFailed"
    }

    /** `YT.PlayerState` values. */
    enum class State(val raw: Int) {
        Unstarted(-1),
        Ended(0),
        Playing(1),
        Paused(2),
        Buffering(3),
        Cued(5),
    }

    sealed interface Message {
        data object Ready : Message
        data class StateChange(val state: State) : Message
        data class Progress(val current: Double, val duration: Double) : Message
        data class Error(val code: Int) : Message
        data object ApiLoadFailed : Message

        companion object {
            fun parse(json: String): Message? {
                val body = runCatching { JSONObject(json) }.getOrNull() ?: return null
                return when (body.optString("event")) {
                    Event.READY -> Ready
                    Event.STATE -> State.entries.firstOrNull { it.raw == body.optInt("data") }?.let(::StateChange)
                    Event.PROGRESS -> body.optJSONObject("data")?.let {
                        Progress(it.optDouble("current", 0.0), it.optDouble("duration", 0.0))
                    }
                    Event.ERROR -> Error(body.optInt("data"))
                    Event.API_LOAD_FAILED -> ApiLoadFailed
                    else -> null
                }
            }
        }
    }

    // Commands

    const val PLAY = "player.playVideo();"
    const val PAUSE = "player.pauseVideo();"

    fun seek(seconds: Double) = "player.seekTo($seconds, true);"

    /** Stops YouTube's video from rendering while background play shows artwork instead; the
     *  sound carries on. */
    fun setVideoHidden(hidden: Boolean) = "setVideoHidden($hidden);"

    /** `videoId` must pass `isValidVideoId` first; it is inserted into JavaScript. */
    fun load(videoId: String, autoplay: Boolean, startingAt: Double = 0.0): String {
        val function = if (autoplay) "loadVideoById" else "cueVideoById"
        return "player.$function({ videoId: '$videoId', startSeconds: $startingAt });"
    }

    private val videoIdCharacters = ('A'..'Z') + ('a'..'z') + ('0'..'9') + '-' + '_'

    fun isValidVideoId(videoId: String) = videoId.isNotEmpty() && videoId.all { it in videoIdCharacters }

    // Page

    private const val MILLISECONDS_PER_SECOND = 1_000

    /** Hosts the official player with YouTube's own controls hidden; the app draws native ones. */
    fun html(origin: String): String {
        val progressInterval = (PlaybackPolicy.PROGRESS_INTERVAL * MILLISECONDS_PER_SECOND).toInt()
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
            $INTERFACE_NAME.post(JSON.stringify({ event: event, data: data }));
          }

          function postProgress() {
            if (!player || !player.getCurrentTime) { return; }
            post('${Event.PROGRESS}', {
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
            if (enabled) { progressTimer = setInterval(postProgress, $progressInterval); }
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
                origin: '$origin',
                widget_referrer: '$origin'
              },
              events: {
                onReady: function () { post('${Event.READY}', null); },
                onStateChange: function (event) {
                  setProgressUpdates(event.data === YT.PlayerState.PLAYING);
                  postProgress();
                  post('${Event.STATE}', event.data);
                },
                onError: function (event) { post('${Event.ERROR}', event.data); }
              }
            });
          }
        </script>
        <script src="${GoogleEndpoint.IFRAME_API}"
                onerror="post('${Event.API_LOAD_FAILED}', null)"></script>
        </body>
        </html>
        """.trimIndent()
    }
}
