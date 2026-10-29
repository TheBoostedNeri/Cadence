package com.nerijus.cadence.catalog

import android.content.Context
import androidx.core.content.edit
import com.nerijus.cadence.model.AppError
import com.nerijus.cadence.model.PlaybackFailure
import com.nerijus.cadence.model.Track
import com.nerijus.cadence.network.YouTubeApiClient

/** Finds the YouTube video for each catalog song. Every new match costs a YouTube search (about
 *  100 quota units), so each song is searched for only once on this device. */
class YouTubeMatcher(context: Context, private val api: YouTubeApiClient) {
    /** Video IDs by Apple catalog song ID. */
    private val store = context.getSharedPreferences("youtube_matches", Context.MODE_PRIVATE)

    /** `track` as its YouTube video. Throws `NoYouTubeMatch` when YouTube has none. */
    suspend fun match(track: Track): Track {
        val songId = track.appleCatalogId ?: track.id
        store.getString(songId, null)?.let { return track.matched(it) }
        val videoId = api.videoIdMatching(track) ?: throw AppError.Playback(PlaybackFailure.NoYouTubeMatch)
        store.edit { putString(songId, videoId) }
        return track.matched(videoId)
    }
}

/** Finds the other version of a YouTube song for Now Playing's Song and Video switch: the music
 *  video of a song playing as audio, or the audio of a music video. Each new lookup costs a
 *  YouTube search (about 100 quota units), so answers, including songs that have no other
 *  version, are kept on this device both ways round. */
class SongVersions(context: Context, private val api: YouTubeApiClient) {
    /** The other version's video ID by `key`; empty when YouTube has none. */
    private val store = context.getSharedPreferences("song_versions", Context.MODE_PRIVATE)

    /** `track` as its music video, or as its audio. Throws `NoMusicVideo` or `NoSongVersion`
     *  when YouTube has none. */
    suspend fun otherVersion(track: Track, wantsVideo: Boolean): Track {
        val key = key(track.id, wantsVideo)
        val videoId = store.getString(key, null) ?: (api.otherVersionId(track, wantsVideo) ?: "").also { found ->
            store.edit {
                putString(key, found)
                if (found.isNotEmpty()) putString(key(found, !wantsVideo), track.id)
            }
        }
        val version = videoId.takeIf(String::isNotEmpty)?.let { api.videos(listOf(it)).firstOrNull() }
            ?: throw AppError.Playback(if (wantsVideo) PlaybackFailure.NoMusicVideo else PlaybackFailure.NoSongVersion)
        // A catalog song keeps Apple's title and artwork, as its first video did.
        return if (track.appleCatalogId == null) version else track.matched(version.id).copy(videoKind = version.videoKind)
    }

    private fun key(videoId: String, wantsVideo: Boolean) = "$videoId>${if (wantsVideo) "video" else "song"}"
}
