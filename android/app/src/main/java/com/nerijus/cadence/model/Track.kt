package com.nerijus.cadence.model

import androidx.core.net.toUri
import com.nerijus.cadence.config.GoogleEndpoint
import com.nerijus.cadence.network.VideoTitle

/** A song. A YouTube video, or a song from Apple's catalog (an album, artist page or genre chart)
 *  waiting for its YouTube video, which the player finds when it comes up to play. */
data class Track(
    /** The YouTube video ID, or Apple's catalog ID while `needsYouTubeMatch`. */
    val id: String,
    val title: String,
    val artist: String,
    /** Small artwork; for YouTube a 16:9 thumbnail without letterboxing, suitable for cropping. */
    val artworkUrl: String?,
    val largeArtworkUrl: String?,
    /** In seconds; null for live streams. */
    val duration: Double?,
    /** The album it's on, for catalog songs and auto-generated YouTube videos. */
    val albumTitle: String? = null,
    val releaseYear: Int? = null,
    /** The Apple catalog song this plays for, for songs picked from Apple's catalog. */
    val appleCatalogId: String? = null,
    /** A catalog song waiting for its YouTube video. Until then `id` is Apple's catalog ID. */
    val needsYouTubeMatch: Boolean = false,
    /** Which recording the video carries; null for songs saved before it was recorded. */
    val videoKind: VideoKind? = null,
) {
    /** Whether this is a song's music video rather than its audio, for Now Playing's Song and
     *  Video switch. Songs saved before Cadence recorded it go by their title. */
    val isMusicVideo: Boolean
        get() = (videoKind ?: if (VideoTitle.isMusicVideo(title)) VideoKind.MusicVideo else VideoKind.Other) == VideoKind.MusicVideo

    /** Music videos show their video in Now Playing; songs show their artwork, played from the
     *  player's hidden spot. */
    val showsVideo: Boolean get() = !needsYouTubeMatch && isMusicVideo

    /** Songs with their video can switch between their audio and their music video. */
    val hasOtherVersions: Boolean get() = !needsYouTubeMatch

    /** The song on YouTube: the video, or a search for it before it has one. */
    val externalUrl: String
        get() = if (needsYouTubeMatch) {
            GoogleEndpoint.RESULTS.toUri().buildUpon().appendQueryParameter("search_query", "$artist $title").build().toString()
        } else {
            GoogleEndpoint.WATCH.toUri().buildUpon().appendQueryParameter("v", id).build().toString()
        }

    /** "Album · 2013", like the lines under Apple Music's top songs. */
    val albumAndYear: String?
        get() = listOfNotNull(albumTitle, releaseYear?.toString()).joinToString(" · ").ifEmpty { null }

    /** This catalog song, now playing as the YouTube video found for it. */
    fun matched(videoId: String) = copy(id = videoId, needsYouTubeMatch = false)

    /** The same song, whichever form it's in: catalog songs match once they have their video. */
    fun isSameSong(other: Track?): Boolean = other != null &&
        (id == other.id || (appleCatalogId != null && appleCatalogId == other.appleCatalogId))
}

/** Which recording a YouTube video carries, best for synced lyrics first. */
enum class VideoKind {
    /** Topic and other audio uploads: the album recording LRCLIB's lyrics are timed against. */
    Audio,
    /** Lyric videos, live versions and anything else the title doesn't call a music video. */
    Other,
    MusicVideo,
}

/** An album from Apple's catalog. YouTube's API has no albums, so they come from there. */
data class Album(
    val id: String,
    val title: String,
    val artist: String,
    val artworkUrl: String?,
    val largeArtworkUrl: String?,
    val releaseYear: Int?,
    /** Catalog songs in album order. */
    val tracks: List<Track>,
)

/** An artist from Apple's catalog, with their songs and releases. */
data class Artist(
    val id: String,
    val name: String,
    val genre: String?,
    /** Most popular first, as Apple ranks them, with one copy of each song. */
    val tracks: List<Track>,
    /** The artist's own albums, newest first. */
    val albums: List<AlbumSummary>,
    /** Singles and EPs, newest first. */
    val singles: List<AlbumSummary>,
    /** Other artists' releases they're featured on. */
    val appearsOn: List<AlbumSummary>,
) {
    val latestRelease: AlbumSummary? get() = (albums + singles).maxByOrNull { it.releaseDate.orEmpty() }
}

/** An album, single or EP listed on an artist's page. */
data class AlbumSummary(
    val id: String,
    val title: String,
    val artworkUrl: String?,
    val largeArtworkUrl: String?,
    /** ISO 8601, so plain string comparison sorts by date. */
    val releaseDate: String?,
    val trackCount: Int?,
    val isSingle: Boolean,
) {
    val releaseYear: Int? get() = releaseDate?.take(4)?.toIntOrNull()
}

data class Playlist(
    val id: String,
    val title: String,
    val summary: String,
    val artworkUrl: String?,
    val largeArtworkUrl: String?,
    val itemCount: Int,
    val privacy: PlaylistPrivacy,
)

enum class PlaylistPrivacy(val apiValue: String, val title: String, val explanation: String) {
    Private("private", "Private", "Only you can see this playlist."),
    Unlisted("unlisted", "Unlisted", "Anyone with the link can see this playlist."),
    Public("public", "Public", "Anyone can search for and see this playlist."),
}

/** A song inside a playlist. `id` is the playlist item ID, needed to remove it. */
data class PlaylistEntry(val id: String, val track: Track)

/** A song the user recently added to one of their playlists. */
data class AddedTrack(val track: Track, val addedAt: String)

data class ChannelProfile(val title: String, val avatarUrl: String?)

/** A song at a position in the play queue. `key` stays with the song as Up Next is reordered,
 *  and tells copies of the same song apart. */
data class QueueItem(val key: String, val index: Int, val track: Track)

/** Number of songs, as "1 song" or "12 songs". */
fun songCount(count: Int) = if (count == 1) "1 song" else "$count songs"
