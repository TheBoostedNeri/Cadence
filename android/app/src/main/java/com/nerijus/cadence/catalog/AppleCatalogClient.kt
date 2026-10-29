package com.nerijus.cadence.catalog

import androidx.core.net.toUri
import com.nerijus.cadence.config.AppleMusicEndpoint
import com.nerijus.cadence.config.AppleMusicLimits
import com.nerijus.cadence.lyrics.SongQuery
import com.nerijus.cadence.model.Album
import com.nerijus.cadence.model.AlbumSummary
import com.nerijus.cadence.model.AppError
import com.nerijus.cadence.model.Artist
import com.nerijus.cadence.model.Track
import com.nerijus.cadence.network.httpRequest
import com.nerijus.cadence.network.looselyMatches
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import org.json.JSONArray
import org.json.JSONObject

/**
 * Albums, artists and genre charts from Apple's public iTunes catalog, which needs no key and
 * uses no YouTube quota. Its songs play through YouTube: each one's video is found as it comes
 * up to play.
 */
class AppleCatalogClient {

    /** The best-selling songs in a genre in `country`, with full details from a lookup. */
    suspend fun topSongs(genreId: Int, country: String): List<Track> {
        val chart = get(
            "${AppleMusicEndpoint.GENRE_CHARTS}$country/rss/topsongs/limit=${AppleMusicLimits.GENRE_CHART_SIZE}/genre=$genreId/json",
        )
        val ids = chartSongIds(chart)
        val detailed = lookup(ids, country).associateBy(Track::id)
        return ids.mapNotNull(detailed::get)
    }

    /** Catalog details for song IDs, in no particular order. */
    private suspend fun lookup(ids: List<String>, country: String): List<Track> =
        ids.chunked(AppleMusicLimits.LOOKUP_BATCH_SIZE).flatMap { batch ->
            results(get(url(AppleMusicEndpoint.LOOKUP, "id" to batch.joinToString(","), "country" to country)))
                .mapNotNull(::track)
        }

    /** The album `track` is from: by catalog ID when the song came from Apple's catalog,
     *  otherwise by matching the artist and title in a search. Null when nothing matches. */
    suspend fun albumContaining(track: Track, country: String): Album? {
        val collectionId = if (track.appleCatalogId != null) {
            results(get(url(AppleMusicEndpoint.LOOKUP, "id" to track.appleCatalogId, "country" to country)))
                .firstOrNull()?.optLongOrNull("collectionId")
        } else {
            catalogSong(track, country)?.optLongOrNull("collectionId")
        }
        return collectionId?.let { album(it, country) }
    }

    /** The catalog song a YouTube video is, found by its artist and title, preferring the same
     *  title. Null when no result is by that artist. */
    private suspend fun catalogSong(track: Track, country: String): JSONObject? {
        val song = SongQuery.from(track.title, track.artist)
        val results = results(
            get(
                url(
                    AppleMusicEndpoint.SEARCH,
                    "term" to "${song.artist} ${song.title}",
                    "entity" to "song",
                    "limit" to AppleMusicLimits.CATALOG_MATCH_CANDIDATES.toString(),
                    "country" to country,
                ),
            ),
        )
        val byArtist = results.filter { it.optString("artistName").looselyMatches(song.artist) }
        return byArtist.firstOrNull { it.optString("trackName").looselyMatches(song.title) } ?: byArtist.firstOrNull()
    }

    suspend fun album(id: Long, country: String): Album? {
        val results = results(
            get(url(AppleMusicEndpoint.LOOKUP, "id" to id.toString(), "entity" to "song", "country" to country)),
        )
        val collection = results.firstOrNull { it.optString("wrapperType") == COLLECTION_WRAPPER } ?: return null
        val title = collection.optString("collectionName").ifEmpty { null } ?: return null
        val songs = results
            .filter { it.optString("kind") == SONG_KIND }
            .sortedWith(compareBy({ it.optInt("discNumber") }, { it.optInt("trackNumber") }))
        return Album(
            id = id.toString(),
            title = title,
            artist = collection.optString("artistName"),
            artworkUrl = artwork(collection, AppleMusicLimits.ARTWORK_PIXELS),
            largeArtworkUrl = artwork(collection, AppleMusicLimits.LARGE_ARTWORK_PIXELS),
            releaseYear = collection.optString("releaseDate").take(YEAR_LENGTH).toIntOrNull(),
            tracks = songs.mapNotNull(::track),
        )
    }

    /** The artist of `track` and their most popular songs: by catalog ID when the song came from
     *  Apple's catalog, otherwise by the song's own catalog entry, then by the artist's name. */
    suspend fun artistOf(track: Track, country: String): Artist? {
        val artistId = when {
            track.appleCatalogId != null ->
                results(get(url(AppleMusicEndpoint.LOOKUP, "id" to track.appleCatalogId, "country" to country)))
                    .firstOrNull()?.optLongOrNull("artistId")
            // The song's own credit beats a name search, which can't tell "A & B" from "A".
            else -> catalogSong(track, country)?.optLongOrNull("artistId") ?: artistId(named = SongQuery.from(track.title, track.artist).artist, country)
        }
        return artistId?.let { artist(it, country) }
    }

    private suspend fun artistId(named: String, country: String): Long? {
        val artists = results(
            get(
                url(
                    AppleMusicEndpoint.SEARCH,
                    "term" to named,
                    "entity" to "musicArtist",
                    "limit" to AppleMusicLimits.CATALOG_MATCH_CANDIDATES.toString(),
                    "country" to country,
                ),
            ),
        ).filter { it.optString("wrapperType") == ARTIST_WRAPPER }
        // "Daft Punk" also finds "Daft Punk is Dead", so the exact name wins.
        val exact = artists.firstOrNull { it.optString("artistName").equals(named, ignoreCase = true) }
        return (exact ?: artists.firstOrNull { it.optString("artistName").looselyMatches(named) })?.optLongOrNull("artistId")
    }

    /** The artist's songs and releases, fetched side by side. */
    private suspend fun artist(id: Long, country: String): Artist? = coroutineScope {
        val songLookup = async { results(get(lookupUrl(id, "song", AppleMusicLimits.ARTIST_SONGS, country))) }
        val releaseLookup = async { results(get(lookupUrl(id, "album", AppleMusicLimits.ARTIST_RELEASES, country))) }
        val songResults = songLookup.await()
        val releaseResults = releaseLookup.await()
        val profile = songResults.firstOrNull { it.optString("wrapperType") == ARTIST_WRAPPER } ?: return@coroutineScope null
        val name = profile.optString("artistName").ifEmpty { null } ?: return@coroutineScope null

        // Hits come back once per album, compilation and reissue they're on; the most popular stays.
        val songs = songResults.mapNotNull(::track).distinctBy { "${it.artist}|${it.title}".lowercase() }

        // Releases come most popular first, with explicit and clean copies; the first copy stays.
        val releases = releaseResults
            .mapNotNull { result -> albumSummary(result)?.let { result to it } }
            .distinctBy { (_, release) -> "${release.isSingle}|${release.title}".lowercase() }
        val own = releases.filter { (result, _) -> result.optLongOrNull("artistId") == id }
            .map { it.second }
            .sortedByDescending { it.releaseDate.orEmpty() }
        val featured = releases.filter { (result, _) -> result.optLongOrNull("artistId") != id }
            .map { it.second }
            .sortedByDescending { it.releaseDate.orEmpty() }

        Artist(
            id = id.toString(),
            name = name,
            genre = profile.optString("primaryGenreName").ifEmpty { null },
            tracks = songs,
            albums = own.filterNot(AlbumSummary::isSingle),
            singles = own.filter(AlbumSummary::isSingle),
            appearsOn = featured,
        )
    }

    // Wire formats

    private fun track(json: JSONObject): Track? {
        if (json.optString("kind") != SONG_KIND) return null
        val id = json.optLongOrNull("trackId")?.toString() ?: return null
        val title = json.optString("trackName").ifEmpty { null } ?: return null
        val artist = json.optString("artistName").ifEmpty { null } ?: return null
        return Track(
            id = id,
            title = title,
            artist = artist,
            artworkUrl = artwork(json, AppleMusicLimits.ARTWORK_PIXELS),
            largeArtworkUrl = artwork(json, AppleMusicLimits.LARGE_ARTWORK_PIXELS),
            duration = json.optDouble("trackTimeMillis").takeUnless(Double::isNaN)?.div(MILLISECONDS_PER_SECOND),
            albumTitle = json.optString("collectionName").ifEmpty { null },
            releaseYear = json.optString("releaseDate").take(YEAR_LENGTH).toIntOrNull(),
            appleCatalogId = id,
            needsYouTubeMatch = true,
        )
    }

    /** An album, single or EP, from an artist lookup. */
    private fun albumSummary(json: JSONObject): AlbumSummary? {
        if (json.optString("wrapperType") != COLLECTION_WRAPPER) return null
        val id = json.optLongOrNull("collectionId") ?: return null
        val name = json.optString("collectionName").ifEmpty { null } ?: return null
        val trackCount = json.optInt("trackCount", 0).takeIf { it > 0 }
        // Apple names singles and EPs "Title - Single" and "Title - EP"; a lone song is a single too.
        val suffix = SINGLE_SUFFIXES.firstOrNull(name::endsWith)
        return AlbumSummary(
            id = id.toString(),
            title = suffix?.let(name::removeSuffix) ?: name,
            artworkUrl = artwork(json, AppleMusicLimits.ARTWORK_PIXELS),
            largeArtworkUrl = artwork(json, AppleMusicLimits.LARGE_ARTWORK_PIXELS),
            releaseDate = json.optString("releaseDate").ifEmpty { null },
            trackCount = trackCount,
            isSingle = suffix != null || trackCount == 1,
        )
    }

    /** Swaps the `100x100bb` size in an Apple artwork URL for a larger square. */
    private fun artwork(json: JSONObject, pixels: Int): String? = json.optString("artworkUrl100").ifEmpty { null }
        ?.replace(AppleMusicLimits.ARTWORK_SIZE_TOKEN, "${pixels}x${pixels}bb")

    /** The iTunes Store's genre charts. Each song sits under `entry`, which is a lone object
     *  instead of a list when a chart has only one song, and missing when it has none. */
    private fun chartSongIds(chart: JSONObject): List<String> {
        val feed = chart.optJSONObject("feed") ?: return emptyList()
        val entry: Any? = feed.opt("entry")
        val entries = when (entry) {
            is JSONArray -> (0 until entry.length()).mapNotNull(entry::optJSONObject)
            is JSONObject -> listOf(entry)
            else -> emptyList()
        }
        return entries.mapNotNull {
            it.optJSONObject("id")?.optJSONObject("attributes")?.optString("im:id")?.ifEmpty { null }
        }
    }

    private fun results(response: JSONObject): List<JSONObject> {
        val results = response.optJSONArray("results") ?: return emptyList()
        return (0 until results.length()).mapNotNull(results::optJSONObject)
    }

    private fun lookupUrl(id: Long, entity: String, limit: Int, country: String) = url(
        AppleMusicEndpoint.LOOKUP,
        "id" to id.toString(),
        "entity" to entity,
        "limit" to limit.toString(),
        "country" to country,
    )

    private fun url(base: String, vararg parameters: Pair<String, String>): String {
        val builder = base.toUri().buildUpon()
        parameters.forEach { (name, value) -> builder.appendQueryParameter(name, value) }
        return builder.build().toString()
    }

    private suspend fun get(url: String): JSONObject {
        val response = httpRequest(url, useCache = true)
        if (!response.isSuccess) throw AppError.Server(response.statusCode, null)
        return runCatching { JSONObject(response.body) }.getOrElse { throw AppError.Decoding }
    }

    private fun JSONObject.optLongOrNull(name: String): Long? = if (has(name) && !isNull(name)) optLong(name) else null

    private companion object {
        const val SONG_KIND = "song"
        const val COLLECTION_WRAPPER = "collection"
        const val ARTIST_WRAPPER = "artist"
        val SINGLE_SUFFIXES = listOf(" - Single", " - EP")
        const val YEAR_LENGTH = 4
        const val MILLISECONDS_PER_SECOND = 1_000.0
    }
}
