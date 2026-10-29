import Foundation

// Wire formats for the YouTube Data API v3. Only the fields the app reads are declared.

nonisolated struct YTListResponse<Item: Decodable & Sendable>: Decodable, Sendable {
    let items: [Item]
    let nextPageToken: String?
}

nonisolated struct YTThumbnail: Decodable, Sendable {
    let url: URL
}

nonisolated struct YTThumbnails: Decodable, Sendable {
    let `default`: YTThumbnail?
    let medium: YTThumbnail?
    let high: YTThumbnail?
    let standard: YTThumbnail?
    let maxres: YTThumbnail?

    /// `medium` and `maxres` are true 16:9 images; `high` and `standard` are letterboxed 4:3.
    var squareSourceURL: URL? { (medium ?? maxres ?? high ?? `default`)?.url }
    var largeURL: URL? { (maxres ?? medium ?? high ?? `default`)?.url }
    var avatarURL: URL? { (medium ?? `default` ?? high)?.url }
}

nonisolated struct YTVideo: Decodable, Sendable {
    let id: String
    let snippet: YTVideoSnippet
    let contentDetails: YTVideoContentDetails?
}

nonisolated struct YTVideoSnippet: Decodable, Sendable {
    let title: String
    let channelTitle: String
    let description: String?
    let thumbnails: YTThumbnails?
    let categoryId: String?
    /// ISO 8601 in UTC, so plain string comparison sorts by date.
    let publishedAt: String?
}

nonisolated struct YTVideoContentDetails: Decodable, Sendable {
    let duration: String?
}

nonisolated struct YTRatingResponse: Decodable, Sendable {
    let items: [YTVideoRating]
}

nonisolated struct YTVideoRating: Decodable, Sendable {
    let videoId: String
    let rating: String

    static let like = "like"
    static let none = "none"
}

nonisolated struct YTSearchResult: Decodable, Sendable {
    let id: YTSearchResultID
}

nonisolated struct YTSearchResultID: Decodable, Sendable {
    let videoId: String?
}

nonisolated struct YTPlaylist: Decodable, Sendable {
    let id: String
    let snippet: YTPlaylistSnippet
    let contentDetails: YTPlaylistContentDetails?
    let status: YTPrivacyStatus?
}

nonisolated struct YTPlaylistSnippet: Decodable, Sendable {
    let title: String
    let description: String?
    let thumbnails: YTThumbnails?
}

nonisolated struct YTPlaylistContentDetails: Decodable, Sendable {
    let itemCount: Int?
}

nonisolated struct YTPrivacyStatus: Codable, Sendable {
    let privacyStatus: String
}

nonisolated struct YTPlaylistItem: Decodable, Sendable {
    let id: String
    let snippet: YTPlaylistItemSnippet?
    let contentDetails: YTPlaylistItemContentDetails?

    var videoID: String? { contentDetails?.videoId ?? snippet?.resourceId?.videoId }
}

nonisolated struct YTPlaylistItemSnippet: Decodable, Sendable {
    let resourceId: YTResourceID?
    /// When the item was added to the playlist (ISO 8601, UTC).
    let publishedAt: String?
}

nonisolated struct YTPlaylistItemContentDetails: Decodable, Sendable {
    let videoId: String?
}

nonisolated struct YTResourceID: Codable, Sendable {
    static let videoKind = "youtube#video"

    let kind: String
    let videoId: String?
    var channelId: String?
}

nonisolated struct YTSubscription: Decodable, Sendable {
    let snippet: YTSubscriptionSnippet
}

nonisolated struct YTSubscriptionSnippet: Decodable, Sendable {
    let resourceId: YTResourceID
}

nonisolated struct YTChannelUploads: Decodable, Sendable {
    let id: String
    let contentDetails: YTChannelContentDetails?
}

nonisolated struct YTChannelContentDetails: Decodable, Sendable {
    let relatedPlaylists: YTRelatedPlaylists?
}

nonisolated struct YTRelatedPlaylists: Decodable, Sendable {
    let uploads: String?
}

nonisolated struct YTChannel: Decodable, Sendable {
    let id: String
    let snippet: YTChannelSnippet
}

nonisolated struct YTChannelSnippet: Decodable, Sendable {
    let title: String
    let thumbnails: YTThumbnails?
}

// MARK: Request bodies

nonisolated struct YTPlaylistInsert: Encodable, Sendable {
    let snippet: YTPlaylistInsertSnippet
    let status: YTPrivacyStatus
}

nonisolated struct YTPlaylistInsertSnippet: Encodable, Sendable {
    let title: String
    let description: String
}

nonisolated struct YTPlaylistUpdate: Encodable, Sendable {
    let id: String
    let snippet: YTPlaylistInsertSnippet
}

nonisolated struct YTPlaylistItemInsert: Encodable, Sendable {
    let snippet: YTPlaylistItemInsertSnippet
}

nonisolated struct YTPlaylistItemInsertSnippet: Encodable, Sendable {
    let playlistId: String
    let resourceId: YTResourceID
}

// MARK: Errors

nonisolated struct GoogleAPIErrorEnvelope: Decodable, Sendable {
    let error: GoogleAPIErrorBody
}

nonisolated struct GoogleAPIErrorBody: Decodable, Sendable {
    let code: Int?
    let message: String?
    let errors: [GoogleAPIErrorDetail]?
}

nonisolated struct GoogleAPIErrorDetail: Decodable, Sendable {
    let reason: String?
}

// MARK: Mapping

nonisolated extension YTVideo {
    var isMusic: Bool { snippet.categoryId == YouTubeAPILimits.musicCategoryID }

    var track: Track {
        // Auto-generated videos name the real artists; their channel may be a distributor's.
        let credits = snippet.description.flatMap(AutoGeneratedCredits.init(description:))
        return Track(
            id: id,
            title: snippet.title.decodingHTMLEntities,
            artist: credits?.artist ?? ArtistName.clean(snippet.channelTitle),
            artworkURL: snippet.thumbnails?.squareSourceURL,
            largeArtworkURL: snippet.thumbnails?.largeURL,
            duration: contentDetails?.duration.flatMap(ISO8601Duration.seconds(from:)),
            albumTitle: credits?.album
        )
    }
}

nonisolated extension YTPlaylist {
    var playlist: Playlist {
        Playlist(
            id: id,
            title: snippet.title.decodingHTMLEntities,
            summary: snippet.description ?? "",
            artworkURL: snippet.thumbnails?.squareSourceURL,
            largeArtworkURL: snippet.thumbnails?.largeURL,
            itemCount: contentDetails?.itemCount ?? 0,
            privacy: status.flatMap { PlaylistPrivacy(rawValue: $0.privacyStatus) } ?? .private
        )
    }
}

nonisolated extension YTChannel {
    var profile: ChannelProfile {
        ChannelProfile(title: snippet.title, avatarURL: snippet.thumbnails?.avatarURL)
    }
}
