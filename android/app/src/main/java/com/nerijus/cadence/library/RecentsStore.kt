package com.nerijus.cadence.library

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nerijus.cadence.config.RecentsPolicy
import com.nerijus.cadence.model.Track
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/** A song played on this device: one per video, updated on each play. */
data class RecentPlay(val track: Track, val lastPlayedAtMillis: Long, val playCount: Int)

/** Play history on this device, newest first, kept in a small JSON file. Failures to save are
 *  ignored on purpose: losing a history entry must never interrupt playback. */
class RecentsStore(context: Context, private val scope: CoroutineScope) {
    private val file = File(context.filesDir, FILE_NAME)
    /** One write at a time, in order, so an older snapshot never lands after a newer one. */
    private val writer = Dispatchers.IO.limitedParallelism(1)

    var plays by mutableStateOf(load())
        private set

    fun record(track: Track) {
        val existing = plays.firstOrNull { it.track.id == track.id }
        val play = RecentPlay(track, System.currentTimeMillis(), (existing?.playCount ?: 0) + 1)
        plays = (listOf(play) + plays.filterNot { it.track.id == track.id }).take(RecentsPolicy.MAX_ENTRIES)
        save()
    }

    fun remove(track: Track) {
        plays = plays.filterNot { it.track.id == track.id }
        save()
    }

    fun clear() {
        plays = emptyList()
        save()
    }

    private fun save() {
        val snapshot = plays
        scope.launch(writer) {
            runCatching { file.writeText(JSONArray(snapshot.map(::toJson)).toString()) }
        }
    }

    private fun load(): List<RecentPlay> = runCatching {
        val array = JSONArray(file.readText())
        (0 until array.length()).mapNotNull { array.optJSONObject(it)?.let(::fromJson) }
    }.getOrDefault(emptyList())

    private fun toJson(play: RecentPlay) = JSONObject()
        .put("videoId", play.track.id)
        .put("title", play.track.title)
        .put("artist", play.track.artist)
        .put("artworkUrl", play.track.artworkUrl)
        .put("largeArtworkUrl", play.track.largeArtworkUrl)
        .put("duration", play.track.duration)
        .put("albumTitle", play.track.albumTitle)
        .put("appleCatalogId", play.track.appleCatalogId)
        .put("lastPlayedAt", play.lastPlayedAtMillis)
        .put("playCount", play.playCount)

    private fun fromJson(json: JSONObject): RecentPlay? {
        val id = json.optString("videoId").ifEmpty { null } ?: return null
        fun text(name: String) = if (json.isNull(name)) null else json.optString(name).ifEmpty { null }
        return RecentPlay(
            track = Track(
                id = id,
                title = json.optString("title"),
                artist = json.optString("artist"),
                artworkUrl = text("artworkUrl"),
                largeArtworkUrl = text("largeArtworkUrl"),
                duration = json.optDouble("duration").takeUnless(Double::isNaN),
                albumTitle = text("albumTitle"),
                appleCatalogId = text("appleCatalogId"),
            ),
            lastPlayedAtMillis = json.optLong("lastPlayedAt"),
            playCount = json.optInt("playCount", 1),
        )
    }

    private companion object {
        const val FILE_NAME = "recent_plays.json"
    }
}
