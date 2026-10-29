package com.nerijus.cadence.playback

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.View
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.core.graphics.createBitmap
import com.nerijus.cadence.BuildConfig
import com.nerijus.cadence.app.AppSettings
import com.nerijus.cadence.config.AppConfig
import com.nerijus.cadence.config.PlaybackPolicy
import com.nerijus.cadence.lyrics.SongQuery
import com.nerijus.cadence.model.AppError
import com.nerijus.cadence.model.PlaybackFailure
import com.nerijus.cadence.model.QueueItem
import com.nerijus.cadence.model.Track
import kotlin.math.abs
import kotlin.time.TimeSource
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

enum class RepeatMode {
    Off,
    /** Back to the first song after the last. */
    All,
    /** The current song over and over. */
    One,
}

/**
 * Owns the play queue and plays it in the official YouTube IFrame player, hosted in one
 * long-lived WebView.
 *
 * YouTube's rules: the player must be visible while it plays, so starting a song opens Now
 * Playing, and closing Now Playing or leaving the app pauses it. The experimental (unofficial)
 * background-play setting lifts that for personal use.
 */
class PlayerController(context: Context, private val config: AppConfig, private val settings: AppSettings) {

    var queue by mutableStateOf<List<Track>>(emptyList())
        private set
    var currentIndex by mutableStateOf<Int?>(null)
        private set
    var status by mutableStateOf<PlaybackStatus>(PlaybackStatus.Idle)
        private set
    /** Seconds into the song. */
    var currentTime by mutableDoubleStateOf(0.0)
        private set
    /** The song's length in seconds, or 0 before it's known. */
    var duration by mutableDoubleStateOf(0.0)
        private set
    var isNowPlayingPresented by mutableStateOf(false)
        private set
    var isShuffled by mutableStateOf(false)
        private set
    var repeatMode by mutableStateOf(RepeatMode.Off)
        private set
    /** Like Apple Music's Autoplay: when the queue runs out, similar songs follow. */
    var isAutoplayEnabled by mutableStateOf(settings.isAutoplayEnabled)
        private set
    /** How many songs at the end of the queue Autoplay added. They wait after everything the
     *  user queued, and Up Next lists them in a section of their own. */
    var autoplayCount by mutableIntStateOf(0)
        private set
    var isFindingAutoplayTracks by mutableStateOf(false)
        private set
    /** Bumped on every seek, so the system's media controls can show the new position. */
    var seekCount by mutableIntStateOf(0)
        private set

    /** Called the first time each queued song actually starts playing. */
    var onTrackStarted: (Track) -> Unit = {}
    /** Finds the YouTube video for a song from Apple's catalog. */
    var matchYouTubeVideo: (suspend (Track) -> Track)? = null
    /** Finds a song's music video (`wantsVideo`), or a music video's audio. */
    var findOtherVersion: (suspend (track: Track, wantsVideo: Boolean) -> Track)? = null
    /** True while the Song and Video switch looks for the other version. */
    var isSwitchingVersion by mutableStateOf(false)
        private set
    /** Finds catalog songs to play after `track` once the queue runs out. */
    var findAutoplayTracks: (suspend (Track) -> List<Track>)? = null

    val currentTrack: Track? get() = currentIndex?.let(queue::getOrNull)
    /** Whether Now Playing holds the player itself: only for a music video, and only while it's
     *  open. Otherwise the player plays from its hidden spot. */
    val showsVideoInNowPlaying: Boolean get() = isNowPlayingPresented && currentTrack?.showsVideo == true
    val isPlaying: Boolean get() = status == PlaybackStatus.Playing || status == PlaybackStatus.Buffering
    val hasNext: Boolean
        get() = currentIndex?.let { it + 1 < queue.size || repeatMode == RepeatMode.All } == true
    val hasPrevious: Boolean get() = currentIndex != null

    private val isBackgroundPlayEnabled: Boolean get() = settings.isBackgroundPlayEnabled

    private val mainThread = Handler(Looper.getMainLooper())
    private val scope = MainScope()

    val webView: PlayerWebView = createWebView(context)

    private var isPlayerReady = false
    private var isPageLoading = false
    private var pendingVideoId: String? = null
    private var pendingStartTime = 0.0
    /** Where the user last seeked to, until the player confirms it got there. */
    private var pendingSeek: PendingSeek? = null
    private var didReportCurrentTrack = false
    /** Finding the current catalog song's YouTube video, before it can load. */
    private var matchJob: Job? = null
    private var autoplayJob: Job? = null
    /** The queue in its own order while shuffled, so turning shuffle off can put it back. */
    private var unshuffledQueue: List<Track>? = null

    init {
        WebView.setWebContentsDebuggingEnabled(BuildConfig.DEBUG)
        webView.keepsPlayingWhenHidden = isBackgroundPlayEnabled
        // Ready before the first song, so it starts sooner.
        loadPlayerPage()
        // The video only renders while Now Playing shows it.
        scope.launch {
            snapshotFlow { showsVideoInNowPlaying }.collect { evaluate(PlayerBridge.setVideoHidden(!it)) }
        }
    }

    private class PendingSeek(val target: Double, val startedAt: TimeSource.Monotonic.ValueTimeMark)

    // Up Next

    /** Where Autoplay's songs start: after the user's songs, and never before the next song. */
    private val autoplayStart: Int
        get() = currentIndex?.let { maxOf(it + 1, queue.size - autoplayCount) } ?: queue.size

    /** The songs the user queued after this one. */
    val upcoming: List<QueueItem>
        get() = currentIndex?.let { queueItems(it + 1 until autoplayStart, PlaybackPolicy.UP_NEXT_PREVIEW_LIMIT) }.orEmpty()

    /** The songs Autoplay will play once the user's run out. */
    val autoplayUpcoming: List<QueueItem>
        get() = currentIndex?.let { queueItems(autoplayStart until queue.size, PlaybackPolicy.AUTOPLAY_PREVIEW_LIMIT) }.orEmpty()

    private fun queueItems(range: IntRange, limit: Int): List<QueueItem> {
        val end = minOf(range.last, range.first + limit - 1)
        if (range.first > end) return emptyList()
        // Copies are counted across the whole queue, so the same song in both sections keeps
        // distinct identities.
        val copiesSeen = mutableMapOf<String, Int>()
        for (index in 0 until range.first) {
            queue.getOrNull(index)?.let { copiesSeen[it.id] = (copiesSeen[it.id] ?: 0) + 1 }
        }
        return (range.first..end).map { index ->
            val track = queue[index]
            val copy = copiesSeen[track.id] ?: 0
            copiesSeen[track.id] = copy + 1
            QueueItem("${track.id}#$copy", index, track)
        }
    }

    /** Autoplay songs that have started playing become ordinary history, so the count covers only
     *  those still ahead. Edits call this first, keeping Autoplay's songs at the end. */
    private fun settleAutoplay() {
        val index = currentIndex ?: return
        autoplayCount = minOf(autoplayCount, queue.size - (index + 1))
    }

    // Queue

    /** Replaces the queue, starts playing and opens Now Playing. */
    fun play(tracks: List<Track>, startIndex: Int = 0) {
        if (startIndex !in tracks.indices) return
        autoplayCount = 0
        unshuffledQueue = null
        var start = startIndex
        queue = if (isShuffled) {
            // Shuffle carries over, like Apple Music: the chosen song, then the rest in any order.
            unshuffledQueue = tracks
            start = 0
            listOf(tracks[startIndex]) + (tracks.take(startIndex) + tracks.drop(startIndex + 1)).shuffled()
        } else {
            tracks
        }
        isNowPlayingPresented = true
        load(start)
    }

    fun playNext(track: Track) {
        val index = currentIndex ?: return play(listOf(track))
        settleAutoplay()
        queue = queue.toMutableList().apply { add(index + 1, track) }
        // Turning shuffle off keeps it next.
        unshuffledQueue?.let { original ->
            val position = indexInUnshuffledQueue(queue[index]) ?: return@let
            unshuffledQueue = original.toMutableList().apply { add(minOf(position + 1, original.size), track) }
        }
    }

    /** Adds `track` after everything queued and before Autoplay's songs. */
    fun playLast(track: Track) {
        if (currentIndex == null) return play(listOf(track))
        settleAutoplay()
        queue = queue.toMutableList().apply { add(queue.size - autoplayCount, track) }
        unshuffledQueue?.let { original ->
            unshuffledQueue = original.toMutableList().apply { add(maxOf(0, original.size - autoplayCount), track) }
        }
    }

    /** Moves one of the user's songs in Up Next. Positions count from the song after this one,
     *  as `upcoming` lists them. */
    fun moveUpNext(from: Int, to: Int) {
        val index = currentIndex ?: return
        settleAutoplay()
        val first = index + 1
        val lastUserSong = autoplayStart - 1
        val source = first + from
        val destination = (first + to).coerceIn(first, lastUserSong)
        if (source !in first..lastUserSong || source == destination) return
        queue = queue.toMutableList().apply { add(destination, removeAt(source)) }
    }

    /** Takes a song out of Up Next, by its place in the queue. */
    fun removeQueued(queueIndex: Int) {
        val index = currentIndex ?: return
        if (queueIndex <= index || queueIndex >= queue.size) return
        settleAutoplay()
        if (queueIndex >= autoplayStart) autoplayCount -= 1
        val removed = queue[queueIndex]
        queue = queue.toMutableList().apply { removeAt(queueIndex) }
        indexInUnshuffledQueue(removed)?.let { position ->
            unshuffledQueue = unshuffledQueue?.toMutableList()?.apply { removeAt(position) }
        }
    }

    /** Moves a queued song up to play right after this one. An Autoplay song becomes one of the
     *  user's. */
    fun playNext(queuedAt: Int) {
        val index = currentIndex ?: return
        if (queuedAt <= index || queuedAt >= queue.size) return
        settleAutoplay()
        if (queuedAt >= autoplayStart) autoplayCount -= 1
        queue = queue.toMutableList().apply { add(index + 1, removeAt(queuedAt)) }
    }

    /** Empties the user's part of Up Next; the current song plays on, and Autoplay after it. */
    fun clearUpNext() {
        val index = currentIndex ?: return
        settleAutoplay()
        val cleared = queue.subList(index + 1, autoplayStart).toList()
        queue = queue.take(index + 1) + queue.drop(autoplayStart)
        cleared.forEach { track ->
            indexInUnshuffledQueue(track)?.let { position ->
                unshuffledQueue = unshuffledQueue?.toMutableList()?.apply { removeAt(position) }
            }
        }
    }

    /** Shuffles the songs after this one, or puts them back in order, carrying on with this song. */
    fun toggleShuffle() {
        val index = currentIndex ?: return
        val current = queue[index]
        val original = unshuffledQueue
        if (original != null) {
            unshuffledQueue = null
            isShuffled = false
            val position = indexInUnshuffledQueue(current, original) ?: return
            // The song may have found its YouTube video since the order was saved.
            queue = original.toMutableList().apply { set(position, current) }
            currentIndex = position
        } else {
            settleAutoplay()
            unshuffledQueue = queue
            isShuffled = true
            // Autoplay's songs stay after the user's, in their own order, like Apple Music.
            queue = queue.take(index + 1) + queue.subList(index + 1, autoplayStart).shuffled() + queue.drop(autoplayStart)
        }
    }

    /** Off, then the whole queue, then just this song, like Apple Music. */
    fun cycleRepeatMode() {
        if (currentTrack == null) return
        repeatMode = when (repeatMode) {
            RepeatMode.Off -> RepeatMode.All
            RepeatMode.All -> RepeatMode.One
            RepeatMode.One -> RepeatMode.Off
        }
        // Back to playing through once: Autoplay can carry on from the end again.
        if (repeatMode == RepeatMode.Off) extendQueueForAutoplayIfNeeded()
    }

    fun toggleAutoplay() {
        isAutoplayEnabled = !isAutoplayEnabled
        settings.isAutoplayEnabled = isAutoplayEnabled
        if (isAutoplayEnabled) extendQueueForAutoplayIfNeeded() else removeAutoplayTracks()
    }

    /** Keeps a few Autoplay songs waiting after the user's, so Up Next shows what plays once they
     *  run out, and tops them up as they're played. Repeating the queue already keeps it going. */
    private fun extendQueueForAutoplayIfNeeded() {
        val find = findAutoplayTracks ?: return
        val seed = queue.lastOrNull() ?: return
        if (!isAutoplayEnabled || repeatMode != RepeatMode.Off || autoplayJob != null || currentIndex == null) return
        settleAutoplay()
        if (autoplayCount >= PlaybackPolicy.AUTOPLAY_REFILL_THRESHOLD) return
        isFindingAutoplayTracks = true
        autoplayJob = scope.launch {
            try {
                runCatching { find(seed) }.getOrNull()?.let { appendAutoplayTracks(it, seed) }
            } finally {
                autoplayJob = null
                isFindingAutoplayTracks = false
            }
        }
    }

    /** Turning Autoplay off takes out the songs it added that haven't played yet. */
    private fun removeAutoplayTracks() {
        autoplayJob?.cancel()
        autoplayJob = null
        isFindingAutoplayTracks = false
        settleAutoplay()
        if (autoplayCount == 0) return
        queue = queue.dropLast(autoplayCount)
        unshuffledQueue = unshuffledQueue?.dropLast(autoplayCount)
        autoplayCount = 0
    }

    private fun appendAutoplayTracks(candidates: List<Track>, seed: Track) {
        // Something else was queued meanwhile, so the queue no longer ends here.
        if (queue.lastOrNull() != seed) return
        val queuedIds = queue.mapNotNull(Track::appleCatalogId).toSet()
        val queuedSongs = queue.map(::songKey).toSet()
        val fresh = candidates
            .filter { it.appleCatalogId !in queuedIds && songKey(it) !in queuedSongs }
            .take(PlaybackPolicy.AUTOPLAY_BATCH_SIZE)
        if (fresh.isEmpty()) return
        settleAutoplay()
        queue = queue + fresh
        unshuffledQueue = unshuffledQueue?.plus(fresh)
        autoplayCount += fresh.size
    }

    /** The song's name without "(feat. X)" or "(Official Video)", to spot one already queued,
     *  whether it's a catalog song or a YouTube video. */
    private fun songKey(track: Track): String {
        val title = if (track.appleCatalogId == null) SongQuery.from(track.title, track.artist).title else track.title
        return SongQuery.removingBracketedText(title).trim().lowercase()
    }

    /** Where `track` sits in the unshuffled order; a catalog song counts once it has its video. */
    private fun indexInUnshuffledQueue(track: Track, original: List<Track>? = unshuffledQueue): Int? =
        original?.indexOfFirst { it.isSameSong(track) }?.takeIf { it >= 0 }

    // Transport

    fun skipTo(index: Int) {
        if (index in queue.indices) load(index)
    }

    fun next() {
        val index = currentIndex ?: return
        // Past the last song only when repeating the queue.
        if (hasNext) load(if (index + 1 < queue.size) index + 1 else 0)
    }

    /** Restarts the song once it's a few seconds in, like Apple Music; otherwise goes back one. */
    fun previous() {
        val index = currentIndex ?: return
        if (currentTime > PlaybackPolicy.RESTART_THRESHOLD || index == 0) seek(0.0) else load(index - 1)
    }

    fun togglePlayPause() {
        if (status.isActive) pause() else resume()
    }

    /** Resumes, replays or retries the current song. Without background play, Now Playing opens
     *  first, since the video must show while it plays. */
    fun resume() {
        val index = currentIndex ?: return
        if (!isBackgroundPlayEnabled) isNowPlayingPresented = true
        when (status) {
            PlaybackStatus.Ended, PlaybackStatus.Idle, is PlaybackStatus.Failed -> load(index)
            else -> evaluate(PlayerBridge.PLAY)
        }
    }

    fun pause() {
        if (status.isActive) evaluate(PlayerBridge.PAUSE)
    }

    /** Swaps the song for its music video, or the video for the song, like YouTube Music's Song
     *  and Video switch. It takes the song's place in the queue and carries on from the same
     *  moment. Throws `NoMusicVideo` or `NoSongVersion` when YouTube has no such version. */
    suspend fun switchVersion(toVideo: Boolean) {
        val index = currentIndex ?: return
        val track = currentTrack ?: return
        val find = findOtherVersion ?: return
        if (!track.hasOtherVersions || isSwitchingVersion) return
        isSwitchingVersion = true
        val version = try {
            find(track, toVideo)
        } finally {
            isSwitchingVersion = false
        }
        // Another song may have started while it was found.
        if (currentIndex != index || queue.getOrNull(index) != track) return
        val position = minOf(currentTime, version.duration ?: currentTime)
        queue = queue.toMutableList().apply { set(index, version) }
        indexInUnshuffledQueue(track)?.let { original ->
            unshuffledQueue = unshuffledQueue?.toMutableList()?.apply { set(original, version) }
        }
        load(index, startingAt = position)
        // The same play carries on, so history keeps just the version the user picked.
        didReportCurrentTrack = true
    }

    fun seek(seconds: Double) {
        currentTime = seconds
        pendingSeek = PendingSeek(seconds, TimeSource.Monotonic.markNow())
        seekCount += 1
        evaluate(PlayerBridge.seek(seconds))
    }

    // Now Playing and the app's visibility

    fun presentNowPlaying() {
        if (currentTrack != null) isNowPlayingPresented = true
    }

    /** The player may not play while hidden, unless background play is on. */
    fun dismissNowPlaying() {
        isNowPlayingPresented = false
        if (!isBackgroundPlayEnabled) pause()
    }

    /** Called when the app leaves the screen. */
    fun handleAppBackgrounded() {
        if (!isBackgroundPlayEnabled) pause()
    }

    /** Turning background play off brings back YouTube's rule: no playback while Now Playing is
     *  closed. */
    fun backgroundPlaySettingChanged() {
        webView.keepsPlayingWhenHidden = isBackgroundPlayEnabled
        if (!isBackgroundPlayEnabled && !isNowPlayingPresented) pause()
    }

    fun release() {
        scope.cancel()
        webView.destroy()
    }

    // Loading

    private fun prepare(index: Int) {
        currentIndex = index
        currentTime = 0.0
        duration = queue[index].duration ?: 0.0
        pendingSeek = null
        didReportCurrentTrack = false
    }

    private fun load(index: Int, startingAt: Double = 0.0) {
        val track = queue.getOrNull(index) ?: return
        prepare(index)
        if (startingAt > 0) {
            // Like a seek, so the new video's first reports from zero don't snap the lyrics back.
            currentTime = startingAt
            pendingSeek = PendingSeek(startingAt, TimeSource.Monotonic.markNow())
        }
        matchJob?.cancel()
        matchJob = null
        status = PlaybackStatus.Loading
        if (track.needsYouTubeMatch) {
            pendingVideoId = null
            matchJob = scope.launch { loadMatch(track, index) }
            return
        }
        if (!PlayerBridge.isValidVideoId(track.id)) {
            status = PlaybackStatus.Failed(AppError.Playback(PlaybackFailure.InvalidVideo))
            return
        }
        if (isPlayerReady) {
            evaluate(PlayerBridge.load(track.id, autoplay = isNowPlayingPresented || isBackgroundPlayEnabled, startingAt = startingAt))
        } else {
            pendingVideoId = track.id
            pendingStartTime = startingAt
            if (!isPageLoading) loadPlayerPage()
        }
    }

    /** Catalog songs come from Apple, so their YouTube video is found first. The match takes the
     *  song's place in the queue, so it's only looked up once. */
    private suspend fun loadMatch(track: Track, index: Int) {
        val match = try {
            val matcher = matchYouTubeVideo ?: throw AppError.Playback(PlaybackFailure.NoYouTubeMatch)
            matcher(track)
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            matchJob = null
            status = PlaybackStatus.Failed(AppError.from(error))
            return
        }
        matchJob = null
        if (currentIndex != index || queue.getOrNull(index) != track) return
        queue = queue.toMutableList().apply { set(index, match) }
        load(index)
    }

    private fun loadPlayerPage() {
        isPlayerReady = false
        isPageLoading = true
        webView.loadDataWithBaseURL(config.playerOrigin, PlayerBridge.html(config.playerOrigin), "text/html", "utf-8", null)
    }

    private fun evaluate(script: String) {
        if (isPlayerReady) webView.evaluateJavascript(script, null)
    }

    // Player events

    /** While the next song's video is being found, the previous video's events are stale. */
    private val isFindingVideo: Boolean get() = matchJob != null

    private fun handle(message: PlayerBridge.Message) {
        when (message) {
            PlayerBridge.Message.Ready -> {
                isPlayerReady = true
                isPageLoading = false
                evaluate(PlayerBridge.setVideoHidden(!showsVideoInNowPlaying))
                pendingVideoId?.let { videoId ->
                    pendingVideoId = null
                    evaluate(PlayerBridge.load(videoId, autoplay = isNowPlayingPresented || isBackgroundPlayEnabled, startingAt = pendingStartTime))
                    pendingStartTime = 0.0
                }
            }
            is PlayerBridge.Message.StateChange -> if (!isFindingVideo) handle(message.state)
            is PlayerBridge.Message.Progress ->
                if (!isFindingVideo) applyReportedPosition(message.current, message.duration)
            is PlayerBridge.Message.Error -> if (!isFindingVideo) {
                status = PlaybackStatus.Failed(
                    AppError.Playback(PlaybackFailure.fromYouTubeErrorCode(message.code), message.code),
                )
            }
            PlayerBridge.Message.ApiLoadFailed -> markPageFailed(AppError.Offline)
        }
    }

    private fun handle(state: PlayerBridge.State) {
        when (state) {
            PlayerBridge.State.Unstarted -> Unit
            PlayerBridge.State.Buffering -> status = PlaybackStatus.Buffering
            PlayerBridge.State.Playing -> {
                if (!isNowPlayingPresented && !isBackgroundPlayEnabled) {
                    // Policy: without background play, never keep playing with Now Playing closed.
                    evaluate(PlayerBridge.PAUSE)
                    return
                }
                status = PlaybackStatus.Playing
                reportTrackStartIfNeeded()
            }
            PlayerBridge.State.Paused, PlayerBridge.State.Cued -> status = PlaybackStatus.Paused
            PlayerBridge.State.Ended -> {
                status = PlaybackStatus.Ended
                val index = currentIndex
                if (repeatMode == RepeatMode.One && index != null) load(index) else next()
            }
        }
    }

    private fun reportTrackStartIfNeeded() {
        val track = currentTrack ?: return
        if (didReportCurrentTrack) return
        didReportCurrentTrack = true
        onTrackStarted(track)
        extendQueueForAutoplayIfNeeded()
    }

    /** Players keep reporting the old position for a moment after a seek; accepting those would
     *  snap the scrubber and lyrics back before they jump forward. */
    private fun applyReportedPosition(current: Double, reportedDuration: Double) {
        if (reportedDuration > 0) duration = reportedDuration
        pendingSeek?.let { seek ->
            val hasLanded = abs(current - seek.target) <= PlaybackPolicy.SEEK_TOLERANCE
            if (!hasLanded && seek.startedAt.elapsedNow() < PlaybackPolicy.seekSettleTimeout) return
            pendingSeek = null
        }
        currentTime = current
    }

    /** The page or YouTube's script didn't load. The next play request loads the page again. */
    private fun markPageFailed(error: AppError) {
        isPlayerReady = false
        isPageLoading = false
        if (currentIndex != null) {
            pendingVideoId = null
            status = PlaybackStatus.Failed(error)
        }
    }

    // Web view

    @SuppressLint("SetJavaScriptEnabled")
    private fun createWebView(context: Context) = PlayerWebView(context).apply {
        setBackgroundColor(Color.BLACK)
        isVerticalScrollBarEnabled = false
        isHorizontalScrollBarEnabled = false
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.mediaPlaybackRequiresUserGesture = false
        addJavascriptInterface(PageMessages(), PlayerBridge.INTERFACE_NAME)
        webViewClient = PageClient()
        webChromeClient = ChromeClient()
    }

    /** Receives the page's messages on WebView's own thread and hands them to the main thread. */
    private inner class PageMessages {
        @JavascriptInterface
        fun post(json: String) {
            val message = PlayerBridge.Message.parse(json) ?: return
            mainThread.post { handle(message) }
        }
    }

    private inner class PageClient : WebViewClient() {
        /** The player page never navigates; YouTube's links stay inside YouTube. */
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = request.isForMainFrame

        override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
            if (request.isForMainFrame) markPageFailed(AppError.Offline)
        }
    }

    private class ChromeClient : WebChromeClient() {
        /** Without this, WebView shows a grey play symbol over the video before it starts. */
        override fun getDefaultVideoPoster(): Bitmap = createBitmap(1, 1)
    }
}

/** The player's web view. With background play on, it never learns that its window went away,
 *  so the page isn't hidden and YouTube's player keeps playing with the app in the background. */
class PlayerWebView(context: Context) : WebView(context) {
    var keepsPlayingWhenHidden = false

    override fun onWindowVisibilityChanged(visibility: Int) {
        if (keepsPlayingWhenHidden && visibility != View.VISIBLE) return
        super.onWindowVisibilityChanged(visibility)
    }
}
