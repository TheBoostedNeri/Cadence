package com.nerijus.cadence.library

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nerijus.cadence.catalog.YouTubeMatcher
import com.nerijus.cadence.model.AppError
import com.nerijus.cadence.model.LoadState
import com.nerijus.cadence.model.Playlist
import com.nerijus.cadence.model.PlaylistEntry
import com.nerijus.cadence.model.PlaylistPrivacy
import com.nerijus.cadence.model.Track
import com.nerijus.cadence.network.YouTubeApiClient
import kotlinx.coroutines.CancellationException

/** The user's playlists, shared by Home, the Playlists tab and the "Add to Playlist" sheet. */
class LibraryStore(private val api: YouTubeApiClient, private val matcher: YouTubeMatcher) {
    var playlists by mutableStateOf<LoadState<List<Playlist>>>(LoadState.Idle)
        private set
    /** A refresh failure while playlists are already on screen. */
    var refreshError by mutableStateOf<AppError?>(null)

    private val loadedPlaylists: List<Playlist>? get() = (playlists as? LoadState.Loaded)?.value

    suspend fun loadPlaylists() {
        val previous = loadedPlaylists
        if (previous == null) playlists = LoadState.Loading
        try {
            playlists = LoadState.Loaded(api.myPlaylists())
        } catch (error: CancellationException) {
            if (previous == null) playlists = LoadState.Idle
            throw error
        } catch (error: Exception) {
            if (previous == null) playlists = LoadState.Failed(AppError.from(error)) else refreshError = AppError.from(error)
        }
    }

    suspend fun createPlaylist(title: String, privacy: PlaylistPrivacy): Playlist {
        val playlist = api.createPlaylist(title, privacy)
        loadedPlaylists?.let { playlists = LoadState.Loaded(listOf(playlist) + it) }
        return playlist
    }

    /** A catalog song gets its YouTube video first, which costs a YouTube search the first time.
     *  Throws `NoYouTubeMatch` when YouTube has no video for it. */
    suspend fun add(track: Track, playlist: Playlist) {
        val video = if (track.needsYouTubeMatch) matcher.match(track) else track
        api.add(video.id, playlist.id)
        update(playlist.id) { it.copy(itemCount = it.itemCount + 1) }
    }

    suspend fun entries(playlist: Playlist): List<PlaylistEntry> = api.entries(playlist.id)

    suspend fun remove(entry: PlaylistEntry, playlist: Playlist) {
        api.removeEntry(entry.id)
        update(playlist.id) { it.copy(itemCount = maxOf(0, it.itemCount - 1)) }
    }

    suspend fun rename(playlist: Playlist, title: String) {
        api.renamePlaylist(playlist, title)
        update(playlist.id) { it.copy(title = title) }
    }

    suspend fun delete(playlist: Playlist) {
        api.deletePlaylist(playlist.id)
        loadedPlaylists?.let { current -> playlists = LoadState.Loaded(current.filterNot { it.id == playlist.id }) }
    }

    /** The latest copy of `playlist`, such as after a rename. */
    fun current(playlist: Playlist): Playlist = loadedPlaylists?.firstOrNull { it.id == playlist.id } ?: playlist

    fun reset() {
        playlists = LoadState.Idle
        refreshError = null
    }

    private fun update(playlistId: String, change: (Playlist) -> Playlist) {
        val current = loadedPlaylists ?: return
        playlists = LoadState.Loaded(current.map { if (it.id == playlistId) change(it) else it })
    }
}

/** Whether the user likes each video, for Now Playing's star. Likes go to the user's YouTube
 *  account, so they also show in YouTube's Liked Music and in Cadence's Home. */
class YouTubeLikes(private val api: YouTubeApiClient, private val isSignedIn: () -> Boolean) {
    /** What YouTube said about each video this session, so the star asks only once. */
    private val likes = mutableStateMapOf<String, Boolean>()

    /** Liking needs a connected account and a YouTube video. */
    fun canLike(track: Track): Boolean = isSignedIn() && !track.needsYouTubeMatch

    fun isLiked(track: Track): Boolean = likes[track.id] == true

    /** Asks YouTube once whether `track` is liked. Costs 1 quota unit; a failure just leaves
     *  the star empty. */
    suspend fun load(track: Track) {
        if (!canLike(track) || track.id in likes) return
        runCatching { api.isLiked(track.id) }.getOrNull()?.let { likes[track.id] = it }
    }

    /** Shows the change at once and takes it back if YouTube refuses it. Costs 50 quota units. */
    suspend fun toggle(track: Track) {
        val wasLiked = isLiked(track)
        likes[track.id] = !wasLiked
        try {
            api.setLiked(!wasLiked, track.id)
        } catch (error: Exception) {
            likes[track.id] = wasLiked
            throw error
        }
    }
}
