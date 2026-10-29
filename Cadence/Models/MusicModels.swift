import Foundation

/// A playable song from one of the supported services.
nonisolated struct Track: Identifiable, Hashable, Codable, Sendable {
    /// The service's own ID: a YouTube video ID, an Apple Music catalog ID or a Spotify track ID.
    let id: String
    let title: String
    let artist: String
    /// Small artwork; for YouTube a 16:9 thumbnail without letterboxing, suitable for cropping.
    let artworkURL: URL?
    let largeArtworkURL: URL?
    let duration: TimeInterval?
    var source: MusicService = .youtube
    /// The album it's on, for catalog songs.
    var albumTitle: String?
    var releaseYear: Int?
    /// For a YouTube song picked from an album: the Apple catalog song it plays for.
    var appleCatalogID: String?
    /// An album song waiting for its YouTube video. Until then `id` is the Apple catalog ID; the
    /// player finds the video when the song is about to play.
    var needsYouTubeMatch = false

    /// The song in its service's own app or website.
    var externalURL: URL {
        switch source {
        case .youtube where needsYouTubeMatch:
            GoogleEndpoint.results.appending(queryItems: [URLQueryItem(name: "search_query", value: "\(artist) \(title)")])
        case .youtube:
            GoogleEndpoint.watch.appending(queryItems: [URLQueryItem(name: "v", value: id)])
        case .appleMusic:
            AppleMusicEndpoint.song.appending(path: id)
        case .spotify:
            SpotifyEndpoint.openTrack.appending(path: id)
        }
    }

    /// YouTube's rules require its player to stay on screen while it plays.
    var requiresVisiblePlayer: Bool { source == .youtube }

    /// The Apple catalog song this is, when known: Apple Music songs, and album songs played on YouTube.
    var catalogSongID: String? { source == .appleMusic ? id : appleCatalogID }

    /// This catalog song, played through YouTube. Apple's title and artwork stay.
    var forYouTubePlayback: Track {
        var track = Track(
            id: catalogSongID ?? id,
            title: title,
            artist: artist,
            artworkURL: artworkURL,
            largeArtworkURL: largeArtworkURL,
            duration: duration,
            source: .youtube,
            albumTitle: albumTitle,
            releaseYear: releaseYear
        )
        track.appleCatalogID = catalogSongID
        track.needsYouTubeMatch = true
        return track
    }

    /// This album song, now playing as the YouTube video found for it.
    func matched(toVideo videoID: String) -> Track {
        var track = Track(
            id: videoID,
            title: title,
            artist: artist,
            artworkURL: artworkURL,
            largeArtworkURL: largeArtworkURL,
            duration: duration,
            source: .youtube,
            albumTitle: albumTitle,
            releaseYear: releaseYear
        )
        track.appleCatalogID = appleCatalogID
        return track
    }
}

/// An album from Apple's catalog. It also serves YouTube songs, since YouTube's API has no albums.
nonisolated struct Album: Identifiable, Hashable, Sendable {
    /// Apple's collection ID.
    let id: String
    let title: String
    let artist: String
    let artworkURL: URL?
    let largeArtworkURL: URL?
    let releaseYear: Int?
    /// Catalog songs in album order.
    let tracks: [Track]
}

/// An artist from Apple's catalog, with their songs and releases.
nonisolated struct Artist: Identifiable, Hashable, Sendable {
    /// Apple's artist ID.
    let id: String
    let name: String
    let genre: String?
    /// Most popular first, as Apple ranks them, with one copy of each song.
    let tracks: [Track]
    /// The artist's own albums, newest first.
    let albums: [AlbumSummary]
    /// Singles and EPs, newest first.
    let singles: [AlbumSummary]
    /// Other artists' releases they're featured on.
    let appearsOn: [AlbumSummary]

    var latestRelease: AlbumSummary? {
        (albums + singles).max { ($0.releaseDate ?? .distantPast) < ($1.releaseDate ?? .distantPast) }
    }
}

/// An album, single or EP listed on an artist's page.
nonisolated struct AlbumSummary: Identifiable, Hashable, Sendable {
    enum Kind: Sendable {
        case album
        /// Singles and EPs, which Apple Music lists together.
        case single
    }

    /// Apple's collection ID.
    let id: String
    let title: String
    let artworkURL: URL?
    let largeArtworkURL: URL?
    let releaseDate: Date?
    let trackCount: Int?
    let kind: Kind

    var releaseYear: Int? {
        releaseDate.map { Calendar.current.component(.year, from: $0) }
    }
}

nonisolated struct Playlist: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    let summary: String
    let artworkURL: URL?
    let largeArtworkURL: URL?
    var itemCount: Int
    /// Nil for services without playlist visibility, such as an Apple Music library.
    let privacy: PlaylistPrivacy?
}

/// A track the user recently added to one of their playlists.
nonisolated struct AddedTrack: Identifiable, Hashable, Sendable {
    let track: Track
    let addedAt: Date

    var id: Track.ID { track.id }
}

/// A track inside a playlist. `id` is the playlist item ID, needed to remove it.
nonisolated struct PlaylistEntry: Identifiable, Hashable, Sendable {
    let id: String
    let track: Track
}

nonisolated enum PlaylistPrivacy: String, CaseIterable, Identifiable, Sendable {
    case `private`
    case unlisted
    case `public`

    var id: String { rawValue }

    var title: String {
        switch self {
        case .private: String(localized: "Private")
        case .unlisted: String(localized: "Unlisted")
        case .public: String(localized: "Public")
        }
    }

    var systemImage: String {
        switch self {
        case .private: "lock.fill"
        case .unlisted: "link"
        case .public: "globe"
        }
    }

    var explanation: String {
        switch self {
        case .private: String(localized: "Only you can see this playlist.")
        case .unlisted: String(localized: "Anyone with the link can see this playlist.")
        case .public: String(localized: "Anyone can search for and see this playlist.")
        }
    }
}

nonisolated struct ChannelProfile: Equatable, Sendable {
    let title: String
    let avatarURL: URL?
}

/// A track at a specific position in the play queue.
nonisolated struct QueueItem: Identifiable, Sendable {
    /// The song, and which copy of it this is when the queue has it more than once. Unlike the
    /// position it stays with the song as Up Next is reordered, so rows keep their identity
    /// while being dragged.
    let id: String
    let index: Int
    let track: Track
}
