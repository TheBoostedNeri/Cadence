package com.nerijus.cadence.lyrics

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.edit
import com.nerijus.cadence.BuildConfig
import com.nerijus.cadence.config.HttpStatus
import com.nerijus.cadence.config.LyricsEndpoint
import com.nerijus.cadence.config.LyricsPolicy
import com.nerijus.cadence.config.NetworkPolicy
import com.nerijus.cadence.model.AppError
import com.nerijus.cadence.model.Track
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/**
 * Time-synced lyrics from LRCLIB (https://lrclib.net), a free, community-maintained database.
 * Lyrics there are user-contributed and unlicensed, so this suits personal use only.
 */
class LyricsService(context: Context) {
    private val offsetStore = context.getSharedPreferences(OFFSETS_STORE, Context.MODE_PRIVATE)
    private val settingsStore = context.getSharedPreferences(SETTINGS_STORE, Context.MODE_PRIVATE)

    /** Per-video timing corrections in seconds; positive values show lyrics later. */
    private val offsets = mutableStateMapOf<String, Double>().apply {
        offsetStore.all.forEach { (trackId, value) -> (value as? Float)?.let { put(trackId, it.toDouble()) } }
    }

    /** Lights up synced lyrics word by word. LRCLIB only times whole lines, so the pace within a
     *  line is estimated. Off by default, as in the iPhone app. */
    var isWordSweepEnabled: Boolean
        get() = wordSweep
        set(enabled) {
            wordSweep = enabled
            settingsStore.edit { putBoolean(WORD_SWEEP_KEY, enabled) }
        }
    private var wordSweep by mutableStateOf(settingsStore.getBoolean(WORD_SWEEP_KEY, false))

    /** Null values remember songs LRCLIB has no lyrics for. The same song can be picked
     *  differently for a recording of another length, so the length is part of the key. */
    private val cache = mutableMapOf<Pair<String, Int?>, Lyrics?>()

    /** The best lyrics for `track` as it plays, `duration` seconds long, or null when LRCLIB has
     *  none. Pass the length the player reports, which can differ from the song's. */
    suspend fun lyrics(track: Track, duration: Double?): Lyrics? {
        val length = duration ?: track.duration
        val key = track.id to length?.roundToInt()
        if (key in cache) return cache[key]
        val query = SongQuery.from(track.title, track.artist)
        val lyrics = bestLyrics(search(mapOf("track_name" to query.title, "artist_name" to query.artist)), length)
            ?: bestLyrics(search(mapOf("q" to "${query.artist} ${query.title}")), length)
        cache[key] = lyrics
        return lyrics
    }

    // Timing

    fun offset(track: Track): Double = offsets[track.id] ?: 0.0

    fun setOffset(offset: Double, track: Track) {
        val rounded = (offset / LyricsPolicy.OFFSET_PRECISION).roundToInt() * LyricsPolicy.OFFSET_PRECISION
        if (rounded == 0.0) offsets.remove(track.id) else offsets[track.id] = rounded
        offsetStore.edit {
            if (rounded == 0.0) remove(track.id) else putFloat(track.id, rounded.toFloat())
        }
    }

    fun adjustOffset(delta: Double, track: Track) {
        setOffset(offset(track) + delta, track)
    }

    // Matching

    private class Record(val duration: Double?, val instrumental: Boolean, val plainLyrics: String?, val syncedLyrics: String?)

    /** Prefers synced lyrics whose recording length is closest to the video's, which also picks
     *  versions timed to the music video when LRCLIB has them. */
    private fun bestLyrics(records: List<Record>, duration: Double?): Lyrics? {
        fun mismatch(record: Record): Double =
            if (duration == null || record.duration == null) 0.0 else abs(record.duration - duration)

        val candidates = records
            .filter { mismatch(it) <= LyricsPolicy.MAX_DURATION_MISMATCH }
            .sortedBy(::mismatch)

        candidates.asSequence()
            .mapNotNull { it.syncedLyrics?.let(LrcParser::lines) }
            .firstOrNull { it.isNotEmpty() }
            ?.let { return Lyrics.Synced(it) }
        candidates.asSequence()
            .mapNotNull { it.plainLyrics?.trim() }
            .firstOrNull { it.isNotEmpty() }
            ?.let { return Lyrics.Plain(it) }
        return if (candidates.any { it.instrumental }) Lyrics.Instrumental else null
    }

    // Transport

    private suspend fun search(parameters: Map<String, String>): List<Record> = withContext(Dispatchers.IO) {
        val query = parameters.entries
            .sortedBy { it.key }
            .joinToString("&") { (name, value) -> "$name=${URLEncoder.encode(value, Charsets.UTF_8.name())}" }
        val connection = URL("${LyricsEndpoint.SEARCH}?$query").openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = NetworkPolicy.CONNECT_TIMEOUT_MILLIS
            connection.readTimeout = NetworkPolicy.READ_TIMEOUT_MILLIS
            // LRCLIB asks clients to identify themselves.
            connection.setRequestProperty("User-Agent", "Cadence/${BuildConfig.VERSION_NAME}")
            val statusCode = connection.responseCode
            if (statusCode !in HttpStatus.success) throw AppError.LyricsService(statusCode)
            val records = JSONArray(connection.inputStream.bufferedReader().use { it.readText() })
            (0 until records.length()).mapNotNull { records.optJSONObject(it)?.let(::record) }
        } catch (error: Throwable) {
            throw AppError.from(error)
        } finally {
            connection.disconnect()
        }
    }

    private fun record(json: JSONObject) = Record(
        duration = json.optDouble("duration").takeUnless(Double::isNaN),
        instrumental = json.optBoolean("instrumental"),
        plainLyrics = json.optStringOrNull("plainLyrics"),
        syncedLyrics = json.optStringOrNull("syncedLyrics"),
    )

    /** `optString` turns JSON null into "null"; these fields are often null. */
    private fun JSONObject.optStringOrNull(name: String) = if (isNull(name)) null else optString(name)

    private companion object {
        const val OFFSETS_STORE = "lyrics_offsets"
        const val SETTINGS_STORE = "settings"
        const val WORD_SWEEP_KEY = "experimental.wordByWordLyrics"
    }
}
