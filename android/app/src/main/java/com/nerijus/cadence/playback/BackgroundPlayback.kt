package com.nerijus.cadence.playback

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.drawable.Icon
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.IBinder
import androidx.compose.runtime.snapshotFlow
import com.nerijus.cadence.MainActivity
import com.nerijus.cadence.R
import com.nerijus.cadence.app.AppSettings
import com.nerijus.cadence.images.ImageLoader
import com.nerijus.cadence.model.Track
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

/**
 * With background play on, shows what's playing in a media notification and on the lock screen,
 * takes headset and system media controls, and keeps the app running with `PlaybackService`
 * while the song plays behind other apps.
 */
class BackgroundPlayback(
    private val context: Context,
    private val player: PlayerController,
    private val settings: AppSettings,
    private val imageLoader: ImageLoader,
    private val scope: CoroutineScope,
) {
    private val notifications = context.getSystemService(NotificationManager::class.java)
    private var session: MediaSession? = null
    private var artwork: Pair<String, Bitmap?>? = null
    private var isServiceRunning = false
    private var job: Job? = null
    /** Whether the app is on screen; a foreground service can only start then. */
    var isAppVisible = false

    init {
        notifications.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, context.getString(R.string.playback_channel_name), NotificationManager.IMPORTANCE_LOW)
                .apply { description = context.getString(R.string.playback_channel_description) },
        )
        active = this
        job = scope.launch {
            snapshotFlow { Snapshot(settings.isBackgroundPlayEnabled, player.currentTrack, player.status, player.seekCount) }
                .collectLatest(::update)
        }
    }

    private data class Snapshot(val isEnabled: Boolean, val track: Track?, val status: PlaybackStatus, val seekCount: Int)

    private suspend fun update(state: Snapshot) {
        val track = state.track
        if (!state.isEnabled || track == null) {
            stop()
            return
        }
        val session = session ?: createSession().also { session = it }
        session.setPlaybackState(playbackState(state.status))
        session.setMetadata(metadata(track, artwork?.takeIf { it.first == track.id }?.second))
        showNotification(track)
        // The artwork arrives after the words, so the notification shows at once.
        if (artwork?.first != track.id) {
            val url = track.largeArtworkUrl ?: track.artworkUrl
            val bitmap = url?.let { imageLoader.load(it, ARTWORK_PIXELS) }
            artwork = track.id to bitmap
            session.setMetadata(metadata(track, bitmap))
            showNotification(track)
        }
    }

    private fun createSession() = MediaSession(context, SESSION_TAG).apply {
        setCallback(object : MediaSession.Callback() {
            override fun onPlay() = player.resume()
            override fun onPause() = player.pause()
            override fun onSkipToNext() = player.next()
            override fun onSkipToPrevious() = player.previous()
            override fun onSeekTo(position: Long) = player.seek(position / MILLIS_PER_SECOND)
            override fun onStop() = player.pause()
        })
        setSessionActivity(openAppIntent())
        isActive = true
    }

    private fun playbackState(status: PlaybackStatus): PlaybackState {
        val state = when (status) {
            PlaybackStatus.Playing -> PlaybackState.STATE_PLAYING
            PlaybackStatus.Loading, PlaybackStatus.Buffering -> PlaybackState.STATE_BUFFERING
            is PlaybackStatus.Failed -> PlaybackState.STATE_ERROR
            PlaybackStatus.Idle, PlaybackStatus.Ended -> PlaybackState.STATE_STOPPED
            PlaybackStatus.Paused -> PlaybackState.STATE_PAUSED
        }
        return PlaybackState.Builder()
            .setActions(
                PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE or
                    PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                    PlaybackState.ACTION_SEEK_TO or PlaybackState.ACTION_STOP,
            )
            .setState(state, (player.currentTime * MILLIS_PER_SECOND).toLong(), if (state == PlaybackState.STATE_PLAYING) 1f else 0f)
            .build()
    }

    private fun metadata(track: Track, bitmap: Bitmap?) = MediaMetadata.Builder()
        .putString(MediaMetadata.METADATA_KEY_TITLE, track.title)
        .putString(MediaMetadata.METADATA_KEY_ARTIST, track.artist)
        .putString(MediaMetadata.METADATA_KEY_ALBUM, track.albumTitle)
        .putLong(MediaMetadata.METADATA_KEY_DURATION, (player.duration * MILLIS_PER_SECOND).toLong())
        .apply { bitmap?.let { putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, it) } }
        .build()

    private fun showNotification(track: Track) {
        val notification = notification(track)
        current = notification
        if (isServiceRunning) {
            notifications.notify(NOTIFICATION_ID, notification)
        } else if (isAppVisible) {
            // Only allowed while the app is on screen; it starts with the first song.
            runCatching { context.startForegroundService(Intent(context, PlaybackService::class.java)) }
                .onSuccess { isServiceRunning = true }
        }
    }

    private fun notification(track: Track): Notification {
        val session = session ?: error("No media session")
        val isPlaying = player.status.isActive
        return Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(track.title)
            .setContentText(track.artist)
            .setLargeIcon(artwork?.takeIf { it.first == track.id }?.second)
            .setContentIntent(openAppIntent())
            .setOngoing(isPlaying)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(action(R.drawable.ic_skip_previous, "Previous", PlaybackService.ACTION_PREVIOUS))
            .addAction(
                if (isPlaying) {
                    action(R.drawable.ic_pause, "Pause", PlaybackService.ACTION_PAUSE)
                } else {
                    action(R.drawable.ic_play, "Play", PlaybackService.ACTION_PLAY)
                },
            )
            .addAction(action(R.drawable.ic_skip_next, "Next", PlaybackService.ACTION_NEXT))
            .setStyle(Notification.MediaStyle().setMediaSession(session.sessionToken).setShowActionsInCompactView(0, 1, 2))
            .build()
    }

    private fun action(icon: Int, title: String, command: String) = Notification.Action.Builder(
        Icon.createWithResource(context, icon),
        title,
        PendingIntent.getService(
            context,
            command.hashCode(),
            Intent(context, PlaybackService::class.java).setAction(command),
            PendingIntent.FLAG_IMMUTABLE,
        ),
    ).build()

    private fun openAppIntent(): PendingIntent = PendingIntent.getActivity(
        context,
        0,
        Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE,
    )

    /** A button in the notification was pressed. */
    fun handle(command: String) {
        when (command) {
            PlaybackService.ACTION_PLAY -> player.resume()
            PlaybackService.ACTION_PAUSE -> player.pause()
            PlaybackService.ACTION_NEXT -> player.next()
            PlaybackService.ACTION_PREVIOUS -> player.previous()
        }
    }

    private fun stop() {
        if (isServiceRunning) {
            context.stopService(Intent(context, PlaybackService::class.java))
            isServiceRunning = false
        }
        current = null
        notifications.cancel(NOTIFICATION_ID)
        session?.release()
        session = null
        artwork = null
    }

    fun release() {
        job?.cancel()
        stop()
        if (active === this) active = null
    }

    companion object {
        private const val CHANNEL_ID = "playback"
        const val NOTIFICATION_ID = 1
        private const val SESSION_TAG = "Cadence"
        private const val ARTWORK_PIXELS = 512
        private const val MILLIS_PER_SECOND = 1_000.0

        /** The one for this app's window, for `PlaybackService` to reach. It only holds the
         *  application context, which lives as long as the app anyway. */
        @SuppressLint("StaticFieldLeak")
        var active: BackgroundPlayback? = null
            private set
        /** The notification the service shows. */
        var current: Notification? = null
            private set
    }
}

/** Keeps the app running while background play plays a song behind other apps, and passes the
 *  notification's buttons to the player. */
class PlaybackService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = BackgroundPlayback.current
        if (notification == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        startForeground(BackgroundPlayback.NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        intent?.action?.let { BackgroundPlayback.active?.handle(it) }
        return START_NOT_STICKY
    }

    companion object {
        const val ACTION_PLAY = "com.nerijus.cadence.action.PLAY"
        const val ACTION_PAUSE = "com.nerijus.cadence.action.PAUSE"
        const val ACTION_NEXT = "com.nerijus.cadence.action.NEXT"
        const val ACTION_PREVIOUS = "com.nerijus.cadence.action.PREVIOUS"
    }
}
