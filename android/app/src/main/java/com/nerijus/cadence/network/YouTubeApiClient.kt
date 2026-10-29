package com.nerijus.cadence.network

import com.nerijus.cadence.auth.GoogleAuthService
import com.nerijus.cadence.config.AppConfig
import com.nerijus.cadence.config.GoogleEndpoint
import com.nerijus.cadence.config.HttpStatus
import com.nerijus.cadence.config.YouTubeApiLimits
import com.nerijus.cadence.config.YouTubeMatchPolicy
import com.nerijus.cadence.lyrics.SongQuery
import com.nerijus.cadence.model.AddedTrack
import com.nerijus.cadence.model.AppError
import com.nerijus.cadence.model.ChannelProfile
import com.nerijus.cadence.model.Playlist
import com.nerijus.cadence.model.PlaylistEntry
import com.nerijus.cadence.model.PlaylistPrivacy
import com.nerijus.cadence.model.Track
import com.nerijus.cadence.model.VideoKind
import kotlin.math.abs
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import org.json.JSONArray
import org.json.JSONObject

/**
 * Client for the YouTube Data API v3. Requests use the connected account's token when there is
 * one; otherwise read-only requests fall back to the shared API key.
 */
class YouTubeApiClient(private val config: AppConfig, private val auth: GoogleAuthService) {

    val hasApiKey: Boolean get() = config.youtubeApiKey != null

    val regionName: String get() = config.regionName

    val chartDescription: String get() = "Most popular music videos in ${config.regionName}"

    // Browse

    /** The most popular music videos in the user's region. Costs 1 quota unit. */
    suspend fun trendingMusic(): List<Track> = send(
        "GET",
        "videos",
        mapOf(
            "part" to "snippet,contentDetails",
            "chart" to "mostPopular",
            "videoCategoryId" to YouTubeApiLimits.MUSIC_CATEGORY_ID,
            "regionCode" to config.regionCode,
            "maxResults" to YouTubeApiLimits.PAGE_SIZE.toString(),
        ),
    ).items().map(YouTubeJson::track)

    /** Embeddable music videos matching `query`, plain songs ahead of their music videos.
     *  Costs ~101 quota units. */
    suspend fun search(query: String): List<Track> {
        // A search costs the same at any size, and a full page of details is still 1 unit, so
        // fetch extra results to find plain uploads YouTube ranks below the music video.
        val results = videoDetails(searchVideoIds(query, YouTubeApiLimits.MAX_PAGE_SIZE))
        val ranked = if (VideoTitle.asksForVideo(query)) results else preferringPlainSongs(results)
        return ranked.take(YouTubeApiLimits.PAGE_SIZE).map(YouTubeJson::track)
    }

    /** Moves each song's audio or lyric video up to where its music video ranked, since music
     *  videos' intros and outros throw synced lyrics off. Different songs keep YouTube's order,
     *  and a music video stays where it is when the results hold no other version of the song. */
    private fun preferringPlainSongs(videos: List<JSONObject>): List<JSONObject> {
        val songs = videos.map { YouTubeJson.track(it).let { track -> SongQuery.from(track.title, track.artist) } }
        val kinds = videos.map(YouTubeJson::kind)
        // Every version of a song takes the place of the version YouTube ranked highest.
        val places = songs.indices.map { index -> songs.indexOfFirst { it.isSameSong(songs[index]) }.takeIf { it >= 0 } ?: index }
        return videos.indices
            .sortedWith(compareBy<Int>({ places[it] }, { kinds[it] }, { it }))
            .map(videos::get)
    }

    /** The video for a song from Apple's catalog, or null when no result carries its title.
     *  Costs ~101 quota units, so `YouTubeMatcher` remembers the answer. */
    suspend fun videoIdMatching(song: Track): String? {
        val title = SongQuery.core(song.title)
        val candidates = videoDetails(searchVideoIds("${song.artist} $title", YouTubeMatchPolicy.CANDIDATES))
            .filter { HtmlEntity.decodeAll(it.snippet.optString("title")).contains(title, ignoreCase = true) }
        // Ties keep YouTube's own order.
        return candidates.maxWithOrNull(compareBy<JSONObject>({ rank(it, song)[0] }, { rank(it, song)[1] }, { rank(it, song)[2] }, { rank(it, song)[3] }))
            ?.optString("id")
    }

    /** The ID of `track`'s music video, or of its audio (a lyric video failing that), or null
     *  when the results hold neither. Costs ~101 quota units, so `SongVersions` remembers it. */
    suspend fun otherVersionId(track: Track, wantsVideo: Boolean): String? {
        val song = SongQuery.from(track.title, track.artist)
        val versions = videoDetails(searchVideoIds("${song.artist} ${song.title}", YouTubeMatchPolicy.VERSION_CANDIDATES))
            .filter { it.optString("id") != track.id && YouTubeJson.track(it).let { found -> SongQuery.from(found.title, found.artist) }.isSameSong(song) }
        // Ties keep YouTube's own order.
        val match = if (wantsVideo) {
            versions.firstOrNull { YouTubeJson.kind(it) == VideoKind.MusicVideo }
        } else {
            versions.filter { YouTubeJson.kind(it) != VideoKind.MusicVideo }.minByOrNull(YouTubeJson::kind)
        }
        return match?.optString("id")
    }

    /** Higher is better: the artist's Topic channel (the album audio), then a video the album
     *  song's length, then anything but a music video, then any channel named after the artist. */
    private fun rank(video: JSONObject, song: Track): List<Int> {
        val channel = video.snippet.optString("channelTitle")
        val isArtistChannel = ArtistName.clean(channel).looselyMatches(song.artist)
        val isTopicChannel = isArtistChannel && ArtistName.isTopicChannel(channel)
        val length = video.optJSONObject("contentDetails")?.optString("duration")?.let(Iso8601Duration::seconds)
        val expected = song.duration
        val hasAlbumLength = length != null && expected != null && abs(length - expected) <= YouTubeMatchPolicy.DURATION_TOLERANCE
        val isMusicVideo = YouTubeJson.kind(video) == VideoKind.MusicVideo
        return listOf(isTopicChannel, hasAlbumLength, !isMusicVideo, isArtistChannel).map { if (it) 1 else 0 }
    }

    private suspend fun searchVideoIds(query: String, count: Int): List<String> = send(
        "GET",
        "search",
        mapOf(
            "part" to "id",
            "type" to "video",
            "videoCategoryId" to YouTubeApiLimits.MUSIC_CATEGORY_ID,
            "videoEmbeddable" to "true",
            "q" to query,
            "maxResults" to count.toString(),
        ),
    ).items().mapNotNull { it.optJSONObject("id")?.optString("videoId")?.ifEmpty { null } }

    /** Full video details in the order given. Unavailable videos are dropped. */
    suspend fun videos(ids: List<String>): List<Track> = videoDetails(ids).map(YouTubeJson::track)

    private suspend fun videoDetails(ids: List<String>): List<JSONObject> {
        val videosById = mutableMapOf<String, JSONObject>()
        for (chunk in ids.distinct().chunked(YouTubeApiLimits.MAX_PAGE_SIZE)) {
            send(
                "GET",
                "videos",
                mapOf(
                    "part" to "snippet,contentDetails",
                    "id" to chunk.joinToString(","),
                    "maxResults" to YouTubeApiLimits.MAX_PAGE_SIZE.toString(),
                ),
            ).items().associateByTo(videosById) { it.optString("id") }
        }
        return ids.mapNotNull(videosById::get)
    }

    // Personal

    /** Music videos the user liked on YouTube, most recent first. Costs 1 quota unit. */
    suspend fun likedMusic(): List<Track> = send(
        "GET",
        "videos",
        mapOf("part" to "snippet,contentDetails", "myRating" to "like", "maxResults" to YouTubeApiLimits.MAX_PAGE_SIZE.toString()),
        requiresAccount = true,
    ).items().filter(::isMusic).map(YouTubeJson::track)

    /** The newest music uploads from channels the user subscribes to, newest first.
     *  Costs roughly 3 quota units plus 1 per channel checked. */
    suspend fun newFromSubscriptions(): List<Track> = coroutineScope {
        val channelIds = send(
            "GET",
            "subscriptions",
            mapOf("part" to "snippet", "mine" to "true", "maxResults" to YouTubeApiLimits.MAX_PAGE_SIZE.toString()),
            requiresAccount = true,
        ).items()
            .mapNotNull { it.snippet.optJSONObject("resourceId")?.optString("channelId")?.ifEmpty { null } }
            .take(YouTubeApiLimits.SUBSCRIPTION_CHANNEL_LIMIT)
        if (channelIds.isEmpty()) return@coroutineScope emptyList()

        val uploadPlaylists = send(
            "GET",
            "channels",
            mapOf(
                "part" to "contentDetails",
                "id" to channelIds.joinToString(","),
                "maxResults" to YouTubeApiLimits.MAX_PAGE_SIZE.toString(),
            ),
            requiresAccount = true,
        ).items().mapNotNull {
            it.optJSONObject("contentDetails")?.optJSONObject("relatedPlaylists")?.optString("uploads")?.ifEmpty { null }
        }
        val videoIds = uploadPlaylists.map { async { latestVideoIds(it) } }.awaitAll().flatten()
        videoDetails(videoIds)
            .filter(::isMusic)
            .sortedByDescending { it.snippet.optString("publishedAt") }
            .take(YouTubeApiLimits.NEW_UPLOADS_LIMIT)
            .map(YouTubeJson::track)
    }

    /** The songs most recently added across the user's playlists, newest first. Costs 1 quota
     *  unit per 50 items read from each playlist, plus 1 for details. */
    suspend fun recentlyAdded(playlists: List<Playlist>): List<AddedTrack> = coroutineScope {
        val items = playlists.take(YouTubeApiLimits.RECENTLY_ADDED_PLAYLIST_LIMIT)
            .map { playlist ->
                async { allPages("playlistItems", mapOf("part" to "snippet,contentDetails", "playlistId" to playlist.id)) }
            }
            .awaitAll()
            .flatten()
        // Newest addition of each video wins when it sits in several playlists. ISO 8601 in UTC,
        // so plain string comparison sorts by date.
        val addedDates = mutableMapOf<String, String>()
        for (item in items) {
            val videoId = videoId(ofPlaylistItem = item) ?: continue
            val addedAt = item.snippet.optString("publishedAt").ifEmpty { null } ?: continue
            if (addedAt > addedDates[videoId].orEmpty()) addedDates[videoId] = addedAt
        }
        val newestIds = addedDates.entries
            .sortedByDescending { it.value }
            .take(YouTubeApiLimits.RECENTLY_ADDED_LIMIT)
            .map { it.key }
        videos(newestIds).mapNotNull { track -> addedDates[track.id]?.let { AddedTrack(track, it) } }
    }

    private suspend fun latestVideoIds(playlistId: String): List<String> = try {
        send(
            "GET",
            "playlistItems",
            mapOf(
                "part" to "contentDetails",
                "playlistId" to playlistId,
                "maxResults" to YouTubeApiLimits.UPLOADS_PER_CHANNEL.toString(),
            ),
            requiresAccount = true,
        ).items().mapNotNull { videoId(ofPlaylistItem = it) }
    } catch (_: AppError) {
        // A channel without public uploads shouldn't hide new music from the others.
        emptyList()
    }

    // Account

    suspend fun myChannel(): ChannelProfile? = send(
        "GET",
        "channels",
        mapOf("part" to "snippet", "mine" to "true"),
        requiresAccount = true,
    ).items().firstOrNull()?.let { channel ->
        ChannelProfile(
            title = channel.snippet.optString("title"),
            avatarUrl = channel.snippet.optJSONObject("thumbnails").url("medium", "default", "high"),
        )
    }

    /** The greeting simply leaves the name out if the channel can't be loaded. */
    suspend fun profileFirstName(): String? =
        runCatching { myChannel() }.getOrNull()?.title?.split(" ")?.firstOrNull()?.ifEmpty { null }

    suspend fun myPlaylists(): List<Playlist> =
        allPages("playlists", mapOf("part" to "snippet,contentDetails,status", "mine" to "true")).map(YouTubeJson::playlist)

    suspend fun entries(playlistId: String): List<PlaylistEntry> {
        val items = allPages("playlistItems", mapOf("part" to "snippet,contentDetails", "playlistId" to playlistId))
        // Private and deleted videos come back without details from /videos, which drops them.
        val tracksById = videos(items.mapNotNull { videoId(ofPlaylistItem = it) }).associateBy(Track::id)
        return items.mapNotNull { item ->
            val track = videoId(ofPlaylistItem = item)?.let(tracksById::get) ?: return@mapNotNull null
            PlaylistEntry(item.optString("id"), track)
        }
    }

    suspend fun createPlaylist(title: String, privacy: PlaylistPrivacy): Playlist {
        val body = JSONObject()
            .put("snippet", JSONObject().put("title", title).put("description", ""))
            .put("status", JSONObject().put("privacyStatus", privacy.apiValue))
        return YouTubeJson.playlist(send("POST", "playlists", mapOf("part" to "snippet,status"), body, requiresAccount = true))
    }

    /** Costs 50 quota units. */
    suspend fun add(videoId: String, playlistId: String) {
        val resource = JSONObject().put("kind", "youtube#video").put("videoId", videoId)
        val body = JSONObject().put("snippet", JSONObject().put("playlistId", playlistId).put("resourceId", resource))
        send("POST", "playlistItems", mapOf("part" to "snippet"), body, requiresAccount = true)
    }

    /** YouTube replaces the whole snippet, so the description goes along unchanged.
     *  Costs 50 quota units. */
    suspend fun renamePlaylist(playlist: Playlist, title: String) {
        val body = JSONObject()
            .put("id", playlist.id)
            .put("snippet", JSONObject().put("title", title).put("description", playlist.summary))
        send("PUT", "playlists", mapOf("part" to "snippet"), body, requiresAccount = true)
    }

    /** Costs 50 quota units. */
    suspend fun deletePlaylist(playlistId: String) {
        send("DELETE", "playlists", mapOf("id" to playlistId), requiresAccount = true)
    }

    suspend fun removeEntry(entryId: String) {
        send("DELETE", "playlistItems", mapOf("id" to entryId), requiresAccount = true)
    }

    // Likes

    /** Whether the user has liked a video. Costs 1 quota unit. */
    suspend fun isLiked(videoId: String): Boolean = send(
        "GET",
        "videos/getRating",
        mapOf("id" to videoId),
        requiresAccount = true,
    ).items().firstOrNull { it.optString("videoId") == videoId }?.optString("rating") == "like"

    /** Likes a video, or takes the like back. Costs 50 quota units. */
    suspend fun setLiked(isLiked: Boolean, videoId: String) {
        send("POST", "videos/rate", mapOf("id" to videoId, "rating" to if (isLiked) "like" else "none"), requiresAccount = true)
    }

    // Transport

    private suspend fun allPages(path: String, query: Map<String, String>): List<JSONObject> {
        val items = mutableListOf<JSONObject>()
        var pageToken: String? = null
        var pages = 0
        do {
            val pageQuery = query + ("maxResults" to YouTubeApiLimits.MAX_PAGE_SIZE.toString()) +
                listOfNotNull(pageToken?.let { "pageToken" to it })
            val response = send("GET", path, pageQuery, requiresAccount = true)
            items += response.items()
            pageToken = response.optString("nextPageToken").ifEmpty { null }
            pages += 1
        } while (pageToken != null && pages < YouTubeApiLimits.MAX_PAGES)
        return items
    }

    private suspend fun send(
        method: String,
        path: String,
        query: Map<String, String>,
        body: JSONObject? = null,
        requiresAccount: Boolean = false,
        isRetry: Boolean = false,
    ): JSONObject {
        val headers = mutableMapOf<String, String>()
        var parameters = query
        val accessToken = auth.validAccessToken()
        when {
            accessToken != null -> headers["Authorization"] = "Bearer $accessToken"
            requiresAccount -> throw AppError.SignInRequired
            config.youtubeApiKey != null -> {
                parameters = query + ("key" to config.youtubeApiKey)
                // Required while the key is restricted to iOS apps.
                headers["X-Ios-Bundle-Identifier"] = config.iosBundleIdentifier
            }
            else -> throw AppError.MissingApiKey
        }
        val response = httpRequest(
            "${GoogleEndpoint.YOUTUBE_API}$path?${formEncode(parameters)}",
            method = method,
            headers = headers,
            body = body?.toString(),
            contentType = JSON_CONTENT_TYPE,
        )
        if (response.statusCode == HttpStatus.UNAUTHORIZED && accessToken != null && !isRetry) {
            auth.refreshAccessToken()
            return send(method, path, query, body, requiresAccount, isRetry = true)
        }
        if (!response.isSuccess) throw apiError(response.statusCode, response.body)
        if (response.body.isBlank()) return JSONObject()
        return runCatching { JSONObject(response.body) }.getOrElse { throw AppError.Decoding }
    }

    private fun apiError(statusCode: Int, body: String): AppError {
        val error = runCatching { JSONObject(body).getJSONObject("error") }.getOrNull()
        val message = error?.optString("message")?.ifEmpty { null }
        return when (error?.optJSONArray("errors")?.optJSONObject(0)?.optString("reason")) {
            "quotaExceeded", "dailyLimitExceeded", "rateLimitExceeded", "userRateLimitExceeded" -> AppError.QuotaExceeded
            "keyInvalid", "keyExpired" -> AppError.InvalidApiKey
            "accessNotConfigured" -> AppError.ApiNotEnabled
            "youtubeSignupRequired", "channelNotFound" -> AppError.ChannelRequired
            else -> when {
                message?.contains("API key", ignoreCase = true) == true -> AppError.InvalidApiKey
                statusCode == HttpStatus.UNAUTHORIZED -> AppError.SessionExpired
                statusCode == HttpStatus.FORBIDDEN -> AppError.Forbidden(message)
                statusCode == HttpStatus.NOT_FOUND -> AppError.NotFound
                else -> AppError.Server(statusCode, message)
            }
        }
    }

    private fun isMusic(video: JSONObject) = video.snippet.optString("categoryId") == YouTubeApiLimits.MUSIC_CATEGORY_ID

    private fun videoId(ofPlaylistItem: JSONObject): String? =
        ofPlaylistItem.optJSONObject("contentDetails")?.optString("videoId")?.ifEmpty { null }
            ?: ofPlaylistItem.snippet.optJSONObject("resourceId")?.optString("videoId")?.ifEmpty { null }
}

private val JSONObject.snippet: JSONObject get() = optJSONObject("snippet") ?: JSONObject()

private fun JSONObject.items(): List<JSONObject> {
    val items: JSONArray = optJSONArray("items") ?: return emptyList()
    return (0 until items.length()).mapNotNull(items::optJSONObject)
}

private fun JSONObject?.url(vararg sizes: String): String? =
    sizes.firstNotNullOfOrNull { size -> this?.optJSONObject(size)?.optString("url")?.ifEmpty { null } }

/** Maps the API's JSON to the app's models. Only the fields the app reads are used. */
private object YouTubeJson {
    fun kind(video: JSONObject): VideoKind {
        val snippet = video.snippet
        val title = HtmlEntity.decodeAll(snippet.optString("title"))
        val isAutoGenerated = AutoGeneratedCredits.parse(snippet.optString("description")) != null
        return when {
            ArtistName.isTopicChannel(snippet.optString("channelTitle")) || isAutoGenerated || VideoTitle.isAudio(title) -> VideoKind.Audio
            VideoTitle.isMusicVideo(title) -> VideoKind.MusicVideo
            else -> VideoKind.Other
        }
    }

    fun track(video: JSONObject): Track {
        val snippet = video.snippet
        val thumbnails = snippet.optJSONObject("thumbnails")
        // Auto-generated videos name the real artists; their channel may be a distributor's.
        val credits = AutoGeneratedCredits.parse(snippet.optString("description"))
        return Track(
            id = video.getString("id"),
            title = HtmlEntity.decodeAll(snippet.optString("title")),
            artist = credits?.artist ?: ArtistName.clean(snippet.optString("channelTitle")),
            // `medium` and `maxres` are true 16:9 images; `high` and `standard` are letterboxed 4:3.
            artworkUrl = thumbnails.url("medium", "maxres", "high", "default"),
            largeArtworkUrl = thumbnails.url("maxres", "medium", "high", "default"),
            duration = video.optJSONObject("contentDetails")?.optString("duration")?.let(Iso8601Duration::seconds),
            albumTitle = credits?.album,
            videoKind = kind(video),
        )
    }

    fun playlist(json: JSONObject): Playlist {
        val snippet = json.snippet
        val thumbnails = snippet.optJSONObject("thumbnails")
        val privacy = json.optJSONObject("status")?.optString("privacyStatus")
        return Playlist(
            id = json.optString("id"),
            title = HtmlEntity.decodeAll(snippet.optString("title")),
            summary = snippet.optString("description"),
            artworkUrl = thumbnails.url("medium", "maxres", "high", "default"),
            largeArtworkUrl = thumbnails.url("maxres", "medium", "high", "default"),
            itemCount = json.optJSONObject("contentDetails")?.optInt("itemCount") ?: 0,
            privacy = PlaylistPrivacy.entries.firstOrNull { it.apiValue == privacy } ?: PlaylistPrivacy.Private,
        )
    }
}
