package com.nerijus.cadence.config

import kotlin.time.Duration.Companion.milliseconds

// The same limits and policies as the iPhone app (Cadence/Services/Configuration/ServiceConstants.swift).

object GoogleEndpoint {
    const val YOUTUBE_API = "https://www.googleapis.com/youtube/v3/"
    const val AUTHORIZE = "https://accounts.google.com/o/oauth2/v2/auth"
    const val TOKEN = "https://oauth2.googleapis.com/token"
    const val REVOKE = "https://oauth2.googleapis.com/revoke"
    const val IFRAME_API = "https://www.youtube.com/iframe_api"
    const val WATCH = "https://www.youtube.com/watch"
    const val RESULTS = "https://www.youtube.com/results"
}

/** Apple's public, keyless catalog services. */
object AppleMusicEndpoint {
    const val SEARCH = "https://itunes.apple.com/search"
    const val LOOKUP = "https://itunes.apple.com/lookup"
    /** Append `{country}/rss/topsongs/limit={count}/genre={id}/json`. */
    const val GENRE_CHARTS = "https://itunes.apple.com/"
}

object AppleMusicLimits {
    /** Search results checked when finding which album or artist a YouTube song is from. */
    const val CATALOG_MATCH_CANDIDATES = 10
    /** The most songs, and releases, Apple's lookup returns for an artist. */
    const val ARTIST_SONGS = 200
    const val ARTIST_RELEASES = 200
    /** The most songs Apple's genre charts list. */
    const val GENRE_CHART_SIZE = 100
    const val LOOKUP_BATCH_SIZE = 150
    /** Artwork comes as `…/100x100bb.jpg`; these are the sizes Cadence asks for instead. */
    const val ARTWORK_PIXELS = 300
    const val LARGE_ARTWORK_PIXELS = 600
    const val ARTWORK_SIZE_TOKEN = "100x100bb"
}

object GoogleScope {
    /** View and manage the user's YouTube account; needed to create and edit playlists. */
    const val YOUTUBE = "https://www.googleapis.com/auth/youtube"
}

/** Links YouTube's API policies require apps to show. */
object LegalLink {
    const val YOUTUBE_TERMS = "https://www.youtube.com/t/terms"
    const val GOOGLE_PRIVACY = "https://policies.google.com/privacy"
    const val MANAGE_ACCESS = "https://myaccount.google.com/permissions"
    const val LRCLIB = "https://lrclib.net"
}

object OAuthPolicy {
    /** Refresh access tokens this long before Google says they expire, in milliseconds. */
    const val EXPIRY_LEEWAY_MILLIS = 60_000L
}

/** Finding the YouTube video for a song from Apple's catalog. */
object YouTubeMatchPolicy {
    /** Search results compared. A search costs 100 quota units however many it returns. */
    const val CANDIDATES = 5
    /** A video this close to the album song's length is likely the album version, in seconds. */
    const val DURATION_TOLERANCE = 10.0
    /** Results searched for a song's other version, its music video or its audio. */
    const val VERSION_CANDIDATES = 10
}

object RecentsPolicy {
    const val MAX_ENTRIES = 200
}

object YouTubeApiLimits {
    const val PAGE_SIZE = 25
    const val MAX_PAGE_SIZE = 50
    const val MAX_PAGES = 4
    /** YouTube's "Music" video category. */
    const val MUSIC_CATEGORY_ID = "10"
    const val MAX_PLAYLIST_TITLE_LENGTH = 150
    /** Subscribed channels checked for new uploads; each costs one quota unit. */
    const val SUBSCRIPTION_CHANNEL_LIMIT = 15
    const val UPLOADS_PER_CHANNEL = 3
    const val NEW_UPLOADS_LIMIT = 20
    /** Playlists scanned for Recently Added; each costs 1 quota unit per 50 songs read. */
    const val RECENTLY_ADDED_PLAYLIST_LIMIT = 10
    /** One page of video details, so the full Recently Added list still costs a single unit. */
    const val RECENTLY_ADDED_LIMIT = 50
}

/** `onError` codes from the YouTube IFrame Player API. */
object YouTubePlayerErrorCode {
    const val INVALID_PARAMETER = 2
    const val NOT_FOUND = 100
    const val EMBEDDING_NOT_ALLOWED = 101
    const val EMBEDDING_NOT_ALLOWED_ALTERNATE = 150
    const val MISSING_CLIENT_IDENTITY = 153
}

object HttpStatus {
    val success = 200..299
    const val UNAUTHORIZED = 401
    const val FORBIDDEN = 403
    const val NOT_FOUND = 404
}

object NetworkPolicy {
    const val CONNECT_TIMEOUT_MILLIS = 15_000
    const val READ_TIMEOUT_MILLIS = 30_000
}

/** The shared download cache, which artwork and API responses go through, so covers stay
 *  between launches. */
object NetworkCache {
    private const val BYTES_PER_MEGABYTE = 1_024 * 1_024
    const val MEMORY_CAPACITY = 32 * BYTES_PER_MEGABYTE
    const val DISK_CAPACITY = 256L * BYTES_PER_MEGABYTE
    const val DIRECTORY = "http"
    /** Artwork downloads running at once; the rest wait their turn. */
    const val PARALLEL_DOWNLOADS = 6
}

object SearchPolicy {
    /** Live search waits this long after the last keystroke, so a query costs one YouTube search
     *  (100 quota units) per pause in typing rather than one per character. */
    val typingPause = 500.milliseconds
    const val MINIMUM_QUERY_LENGTH = 2
}

object PlaybackPolicy {
    /** "Previous" restarts the current track when played past this point, in seconds. */
    const val RESTART_THRESHOLD = 3.0
    /** How often the player reports its position, in seconds. */
    const val PROGRESS_INTERVAL = 0.25
    const val MINIMUM_SLIDER_RANGE = 1.0
    /** A position report this close to a seek target means the seek has landed, in seconds. */
    const val SEEK_TOLERANCE = 2.0
    /** Give up waiting for a seek to land after this long and trust the player again. */
    val seekSettleTimeout = 1_200.milliseconds
    const val UP_NEXT_PREVIEW_LIMIT = 20
    /** Songs Autoplay adds at a time. */
    const val AUTOPLAY_BATCH_SIZE = 10
    /** Autoplay plays this many similar songs by other artists for each one by the same artist. */
    const val AUTOPLAY_SIMILAR_PER_ARTIST_SONG = 2
    /** Autoplay finds more once fewer than this many of its songs are still to play. */
    const val AUTOPLAY_REFILL_THRESHOLD = 3
    /** Autoplay songs Up Next lists. */
    const val AUTOPLAY_PREVIEW_LIMIT = 10
}

object LyricsEndpoint {
    const val SEARCH = "https://lrclib.net/api/search"
}

object LyricsPolicy {
    /** Ignore lyrics recorded for a version this much longer or shorter than the video, in
     *  seconds (music videos often add intros, so this is generous). */
    const val MAX_DURATION_MISMATCH = 90.0
    const val OFFSET_STEP = 0.5
    /** Highlight each line this much before its timestamp, as Apple Music does. */
    const val HIGHLIGHT_LEAD = 0.35
    /** Slowest the estimated word sweep may go, so pauses before the next line don't drag it out. */
    const val MAX_SECONDS_PER_CHARACTER = 0.12
    /** Typical singing pace, used for the last line, which has no next line to end at. */
    const val FALLBACK_SECONDS_PER_CHARACTER = 0.07
    const val MINIMUM_SWEEP_DURATION = 0.5
    const val OFFSET_PRECISION = 0.1
}
