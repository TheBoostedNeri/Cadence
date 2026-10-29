package com.nerijus.cadence.catalog

import com.nerijus.cadence.config.AppConfig
import com.nerijus.cadence.config.PlaybackPolicy
import com.nerijus.cadence.model.Album
import com.nerijus.cadence.model.Artist
import com.nerijus.cadence.model.Track
import com.nerijus.cadence.network.looselyMatches

/** Albums, artists and genre charts from Apple's free catalog, since YouTube's API has none.
 *  Pages already looked up are kept for the rest of the session. */
class CatalogBrowser(private val config: AppConfig, private val client: AppleCatalogClient = AppleCatalogClient()) {
    private val albums = mutableMapOf<String, Album?>()
    private val albumsById = mutableMapOf<String, Album?>()
    private val artists = mutableMapOf<String, Artist?>()
    private val genreCharts = mutableMapOf<Int, List<Track>>()

    private val country: String get() = config.regionCode.lowercase()

    /** The album `track` is from, or null when Apple's catalog has none by its artist. */
    suspend fun albumContaining(track: Track): Album? {
        val key = track.appleCatalogId ?: track.id
        if (key in albums) return albums[key]
        return client.albumContaining(track, country).also { albums[key] = it }
    }

    /** An album picked by its catalog ID, such as from an artist's page. */
    suspend fun album(id: String): Album? {
        if (id in albumsById) return albumsById[id]
        val numericId = id.toLongOrNull() ?: return null
        return client.album(numericId, country).also { albumsById[id] = it }
    }

    /** A genre's best-selling songs in the user's region, most popular first. */
    suspend fun topSongs(genre: MusicGenre): List<Track> =
        genreCharts[genre.id] ?: client.topSongs(genre.id, country).also { genreCharts[genre.id] = it }

    /** The artist of `track` and their songs, or null when Apple's catalog has no such artist. */
    suspend fun artistOf(track: Track): Artist? {
        val key = track.appleCatalogId ?: track.id
        if (key in artists) return artists[key]
        return client.artistOf(track, country).also { artists[key] = it }
    }

    /** Songs for Autoplay to play after `track`: popular songs in the same genre, with about one
     *  in three by the same artist, like a radio station built from the song. Only the artist's
     *  songs when the genre has no chart, and none when Apple doesn't know the artist. */
    suspend fun autoplayTracks(track: Track): List<Track> {
        val artist = artistOf(track) ?: return emptyList()
        val genre = artist.genre?.let(MusicGenre::matching) ?: return artist.tracks
        val chart = runCatching { topSongs(genre) }.getOrNull() ?: return artist.tracks
        // Shuffled, so each top-up brings different songs rather than the chart's top every time.
        val similar = chart.filterNot { it.artist.looselyMatches(artist.name) }.shuffled()
        return interleave(similar, artist.tracks, PlaybackPolicy.AUTOPLAY_SIMILAR_PER_ARTIST_SONG)
    }

    /** `run` songs from `main`, then one from `other`, and so on, until both run out. */
    private fun interleave(main: List<Track>, other: List<Track>, run: Int): List<Track> {
        val result = mutableListOf<Track>()
        var mainIndex = 0
        var otherIndex = 0
        while (mainIndex < main.size || otherIndex < other.size) {
            val runEnd = minOf(mainIndex + run, main.size)
            result += main.subList(mainIndex, runEnd)
            mainIndex = runEnd
            if (otherIndex < other.size) result += other[otherIndex++]
        }
        return result
    }
}
