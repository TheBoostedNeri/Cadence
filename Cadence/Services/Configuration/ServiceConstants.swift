import Foundation

nonisolated enum GoogleEndpoint {
    static let youtubeAPI = URL(string: "https://www.googleapis.com/youtube/v3/")!
    static let authorize = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let token = URL(string: "https://oauth2.googleapis.com/token")!
    static let revoke = URL(string: "https://oauth2.googleapis.com/revoke")!
    static let iframeAPI = URL(string: "https://www.youtube.com/iframe_api")!
    static let watch = URL(string: "https://www.youtube.com/watch")!
    static let results = URL(string: "https://www.youtube.com/results")!
}

/// Apple's public, keyless catalog services, which work without MusicKit.
nonisolated enum AppleMusicEndpoint {
    static let search = URL(string: "https://itunes.apple.com/search")!
    static let lookup = URL(string: "https://itunes.apple.com/lookup")!
    /// Append `{country}/music/most-played/{count}/songs.json`.
    static let charts = URL(string: "https://rss.marketingtools.apple.com/api/v2/")!
    static let song = URL(string: "https://music.apple.com/song/")!
    /// Append `{country}/rss/topsongs/limit={count}/genre={id}/json`. The newer charts feed has
    /// no genres, so Discover uses this older iTunes Store one.
    static let genreCharts = URL(string: "https://itunes.apple.com/")!
}

nonisolated enum AppleMusicLimits {
    static let searchResults = 25
    /// Search results checked when finding which album or artist a YouTube song is from.
    static let catalogMatchCandidates = 10
    /// The most songs, and releases, Apple's lookup returns for an artist.
    static let artistSongs = 200
    static let artistReleases = 200
    static let chartSize = 25
    /// The most songs Apple's genre charts list.
    static let genreChartSize = 100
    static let lookupBatchSize = 150
    static let recentlyAddedLimit = 50
    /// Artwork comes as `…/100x100bb.jpg`; these are the sizes Cadence asks for instead.
    static let artworkPixels = 300
    static let largeArtworkPixels = 600
    static let artworkSizeToken = "100x100bb"
}

nonisolated enum SpotifyEndpoint {
    static let openTrack = URL(string: "https://open.spotify.com/track/")!
}

nonisolated enum GoogleScope {
    /// View and manage the user's YouTube account; needed to create and edit playlists.
    static let youtube = "https://www.googleapis.com/auth/youtube"
}

/// Links YouTube's API policies require apps to show.
nonisolated enum LegalLink {
    static let youtubeTerms = URL(string: "https://www.youtube.com/t/terms")!
    static let googlePrivacy = URL(string: "https://policies.google.com/privacy")!
    static let manageAccess = URL(string: "https://myaccount.google.com/permissions")!
}

nonisolated enum YouTubeAPILimits {
    static let pageSize = 25
    static let maxPageSize = 50
    static let maxPages = 4
    /// YouTube's "Music" video category.
    static let musicCategoryID = "10"
    static let maxPlaylistTitleLength = 150
    /// Subscribed channels checked for new uploads; each costs one quota unit.
    static let subscriptionChannelLimit = 15
    static let uploadsPerChannel = 3
    static let newUploadsLimit = 20
    /// Playlists scanned for Recently Added; each costs 1 quota unit per 50 songs read.
    static let recentlyAddedPlaylistLimit = 10
    /// One page of video details, so the full Recently Added list still costs a single unit.
    static let recentlyAddedLimit = 50
}

/// Finding the YouTube video for a song from an Apple album.
nonisolated enum YouTubeMatchPolicy {
    /// Search results compared. A search costs 100 quota units however many it returns.
    static let candidates = 5
    /// A video this close to the album song's length is likely the album version.
    static let durationTolerance: TimeInterval = 10
}

/// `onError` codes from the YouTube IFrame Player API.
nonisolated enum YouTubePlayerErrorCode {
    static let invalidParameter = 2
    static let notFound = 100
    static let embeddingNotAllowed = 101
    static let embeddingNotAllowedAlternate = 150
    static let missingClientIdentity = 153
}

nonisolated enum HTTPStatus {
    static let success = 200..<300
    static let unauthorized = 401
    static let forbidden = 403
    static let notFound = 404
}

/// The shared download cache, which artwork goes through. The system's default is a few
/// megabytes, too small to keep covers between launches, so screens would fetch them all again.
nonisolated enum NetworkCache {
    private static let bytesPerMegabyte = 1_024 * 1_024
    static let memoryCapacity = 32 * bytesPerMegabyte
    static let diskCapacity = 256 * bytesPerMegabyte
}

nonisolated enum OAuthPolicy {
    /// Refresh access tokens this long before Google says they expire.
    static let expiryLeeway: TimeInterval = 60
}

nonisolated enum SearchPolicy {
    /// Live search waits this long after the last keystroke, so a query costs one YouTube search
    /// (100 quota units) per pause in typing rather than one per character.
    static let typingPause: Duration = .milliseconds(500)
    static let minimumQueryLength = 2
}

nonisolated enum PlaybackPolicy {
    /// "Previous" restarts the current track when played past this point.
    static let restartThreshold: TimeInterval = 3
    /// How often the player reports its position; short enough for lyric lines to land on time.
    static let progressInterval: TimeInterval = 0.25
    static let minimumSliderRange: TimeInterval = 1
    /// A position report this close to a seek target means the seek has landed.
    static let seekTolerance: TimeInterval = 2
    /// Give up waiting for a seek to land after this long and trust the player again.
    static let seekSettleTimeout: TimeInterval = 1.2
    /// Gap between attempts to restart YouTube once iOS has paused it on backgrounding.
    static let backgroundResumeDelay: Duration = .milliseconds(500)
    static let backgroundResumeAttempts = 3
    /// How long a play request may go unanswered before the player is rebuilt.
    static let playStartTimeout: Duration = .milliseconds(1500)
    /// Pauses within this long of leaving the screen are iOS's, not the user's.
    static let backgroundPauseWindow: TimeInterval = 3
    static let upNextPreviewLimit = 20
    static let fullVolume: Double = 1
    /// Songs Autoplay adds at a time.
    static let autoplayBatchSize = 10
    /// Autoplay plays this many similar songs by other artists for each one by the same artist.
    static let autoplaySimilarPerArtistSong = 2
    /// Autoplay finds more once fewer than this many of its songs are still to play.
    static let autoplayRefillThreshold = 3
    /// Autoplay songs Up Next lists.
    static let autoplayPreviewLimit = 10
    /// How far VoiceOver's swipe up and down moves the position.
    static let accessibilitySeekStep: TimeInterval = 10
}

nonisolated enum RecentsPolicy {
    static let maxEntries = 200
}

nonisolated enum LyricsEndpoint {
    static let search = URL(string: "https://lrclib.net/api/search")!
    static let homepage = URL(string: "https://lrclib.net")!
}

nonisolated enum LyricsPolicy {
    /// Ignore lyrics recorded for a version this much longer or shorter than the video
    /// (music videos often add intros, so this is generous).
    static let maxDurationMismatch: TimeInterval = 90
    static let offsetStep: TimeInterval = 0.5
    /// Highlight each line this much before its timestamp, as Apple Music does.
    static let highlightLead: TimeInterval = 0.35
    /// Slowest the estimated word sweep may go, so pauses before the next line don't drag it out.
    static let maxSecondsPerCharacter: TimeInterval = 0.12
    /// Typical singing pace, used for the last line, which has no next line to end at.
    static let fallbackSecondsPerCharacter: TimeInterval = 0.07
    static let minimumSweepDuration: TimeInterval = 0.5
    static let offsetPrecision: TimeInterval = 0.1
}
