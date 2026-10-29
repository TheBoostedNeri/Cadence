import AuthenticationServices
import Foundation
import Observation
import SwiftUI

/// Client for the YouTube Data API v3.
///
/// Requests use the connected account's OAuth token when there is one; otherwise read-only
/// requests fall back to the bundled API key.
@Observable
final class YouTubeAPIClient {
    @ObservationIgnored private let config: AppConfig
    @ObservationIgnored private let auth: GoogleAuthService
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let decoder = JSONDecoder()
    @ObservationIgnored private let encoder = JSONEncoder()

    init(config: AppConfig, auth: GoogleAuthService, session: URLSession = .shared) {
        self.config = config
        self.auth = auth
        self.session = session
    }

    var hasAPIKey: Bool { config.youtubeAPIKey != nil }

    var regionName: String { config.regionName }

    // MARK: Browse

    /// The most popular music videos in the user's region. Costs 1 quota unit.
    func trendingMusic() async throws -> [Track] {
        let response: YTListResponse<YTVideo> = try await send(.get, "videos", query: [
            "part": "snippet,contentDetails",
            "chart": "mostPopular",
            "videoCategoryId": YouTubeAPILimits.musicCategoryID,
            "regionCode": config.regionCode,
            "maxResults": String(YouTubeAPILimits.pageSize),
        ])
        return response.items.map(\.track)
    }

    /// Embeddable music videos matching `query`. Costs ~101 quota units, so only call on submit.
    func search(_ query: String) async throws -> [Track] {
        let response: YTListResponse<YTSearchResult> = try await send(.get, "search", query: [
            "part": "id",
            "type": "video",
            "videoCategoryId": YouTubeAPILimits.musicCategoryID,
            "videoEmbeddable": "true",
            "q": query,
            "maxResults": String(YouTubeAPILimits.pageSize),
        ])
        return try await videos(ids: response.items.compactMap(\.id.videoId))
    }

    /// The video for a song from Apple's catalog, or nil when no result carries its title.
    /// Costs ~101 quota units, so `YouTubeMatcher` remembers the answer.
    func videoID(matching song: Track) async throws -> String? {
        let title = SongTitle.core(of: song.title)
        let response: YTListResponse<YTSearchResult> = try await send(.get, "search", query: [
            "part": "id",
            "type": "video",
            "videoCategoryId": YouTubeAPILimits.musicCategoryID,
            "videoEmbeddable": "true",
            "q": "\(song.artist) \(title)",
            "maxResults": String(YouTubeMatchPolicy.candidates),
        ])
        let candidates = try await videoDetails(ids: response.items.compactMap(\.id.videoId))
            .filter { $0.snippet.title.decodingHTMLEntities.looselyContains(title) }
        // Ties keep YouTube's own order.
        return candidates.max { Self.rank($0, for: song) < Self.rank($1, for: song) }?.id
    }

    /// Higher is better: the artist's Topic channel (the album audio), then a video the album
    /// song's length, then any channel named after the artist.
    private static func rank(_ video: YTVideo, for song: Track) -> (Int, Int, Int) {
        let channel = video.snippet.channelTitle
        let isArtistChannel = ArtistName.clean(channel).looselyMatches(song.artist)
        let isTopicChannel = isArtistChannel && ArtistName.isTopicChannel(channel)
        let length = video.contentDetails?.duration.flatMap(ISO8601Duration.seconds(from:))
        let hasAlbumLength = if let length, let expected = song.duration {
            abs(length - expected) <= YouTubeMatchPolicy.durationTolerance
        } else {
            false
        }
        return (isTopicChannel ? 1 : 0, hasAlbumLength ? 1 : 0, isArtistChannel ? 1 : 0)
    }

    /// Full video details in the order given. Unavailable videos are dropped.
    func videos(ids: [String]) async throws -> [Track] {
        try await videoDetails(ids: ids).map(\.track)
    }

    private func videoDetails(ids: [String]) async throws -> [YTVideo] {
        var videosByID: [String: YTVideo] = [:]
        for start in stride(from: 0, to: ids.count, by: YouTubeAPILimits.maxPageSize) {
            let chunk = ids[start..<min(start + YouTubeAPILimits.maxPageSize, ids.count)]
            let response: YTListResponse<YTVideo> = try await send(.get, "videos", query: [
                "part": "snippet,contentDetails",
                "id": chunk.joined(separator: ","),
                "maxResults": String(YouTubeAPILimits.maxPageSize),
            ])
            for video in response.items {
                videosByID[video.id] = video
            }
        }
        return ids.compactMap { videosByID[$0] }
    }

    // MARK: Personal

    /// Music videos the user liked on YouTube, most recent first. Costs 1 quota unit.
    func likedMusic() async throws -> [Track] {
        let response: YTListResponse<YTVideo> = try await send(.get, "videos", query: [
            "part": "snippet,contentDetails",
            "myRating": "like",
            "maxResults": String(YouTubeAPILimits.maxPageSize),
        ], requiresAccount: true)
        return response.items.filter(\.isMusic).map(\.track)
    }

    /// The newest music uploads from channels the user subscribes to, newest first.
    /// Costs roughly 3 quota units plus 1 per channel checked.
    func newFromSubscriptions() async throws -> [Track] {
        let subscriptions: YTListResponse<YTSubscription> = try await send(.get, "subscriptions", query: [
            "part": "snippet",
            "mine": "true",
            "maxResults": String(YouTubeAPILimits.maxPageSize),
        ], requiresAccount: true)
        let channelIDs = subscriptions.items
            .compactMap(\.snippet.resourceId.channelId)
            .prefix(YouTubeAPILimits.subscriptionChannelLimit)
        guard !channelIDs.isEmpty else { return [] }

        let channels: YTListResponse<YTChannelUploads> = try await send(.get, "channels", query: [
            "part": "contentDetails",
            "id": channelIDs.joined(separator: ","),
            "maxResults": String(YouTubeAPILimits.maxPageSize),
        ], requiresAccount: true)
        let uploadPlaylists = channels.items.compactMap(\.contentDetails?.relatedPlaylists?.uploads)

        let videoIDs = try await withThrowingTaskGroup(of: [String].self) { group in
            for playlistID in uploadPlaylists {
                group.addTask { try await self.latestVideoIDs(inPlaylist: playlistID) }
            }
            var ids: [String] = []
            for try await batch in group {
                ids += batch
            }
            return ids
        }

        return try await videoDetails(ids: videoIDs)
            .filter(\.isMusic)
            .sorted { ($0.snippet.publishedAt ?? "") > ($1.snippet.publishedAt ?? "") }
            .prefix(YouTubeAPILimits.newUploadsLimit)
            .map(\.track)
    }

    /// The songs most recently added across the user's playlists, newest first.
    /// Costs 1 quota unit per 50 items read from each playlist, plus 1 for details.
    func recentlyAdded(to playlists: [Playlist]) async throws -> [AddedTrack] {
        let items = try await withThrowingTaskGroup(of: [YTPlaylistItem].self) { group in
            for playlist in playlists.prefix(YouTubeAPILimits.recentlyAddedPlaylistLimit) {
                group.addTask {
                    try await self.allPages("playlistItems", query: [
                        "part": "snippet,contentDetails",
                        "playlistId": playlist.id,
                    ])
                }
            }
            var all: [YTPlaylistItem] = []
            for try await batch in group {
                all += batch
            }
            return all
        }

        // Newest addition of each video wins when it sits in several playlists.
        var addedDates: [String: Date] = [:]
        for item in items {
            guard let videoID = item.videoID,
                  let published = item.snippet?.publishedAt,
                  let addedAt = try? Date(published, strategy: .iso8601)
            else { continue }
            addedDates[videoID] = max(addedDates[videoID] ?? .distantPast, addedAt)
        }
        let newestIDs = addedDates
            .sorted { $0.value > $1.value }
            .prefix(YouTubeAPILimits.recentlyAddedLimit)
            .map(\.key)

        return try await videos(ids: newestIDs).compactMap { track in
            addedDates[track.id].map { AddedTrack(track: track, addedAt: $0) }
        }
    }

    private func latestVideoIDs(inPlaylist playlistID: String) async throws -> [String] {
        do {
            let response: YTListResponse<YTPlaylistItem> = try await send(.get, "playlistItems", query: [
                "part": "contentDetails",
                "playlistId": playlistID,
                "maxResults": String(YouTubeAPILimits.uploadsPerChannel),
            ], requiresAccount: true)
            return response.items.compactMap(\.videoID)
        } catch {
            if error.isCancellation { throw error }
            // A channel without public uploads shouldn't hide new music from the others.
            return []
        }
    }

    // MARK: Account

    func myChannel() async throws -> ChannelProfile? {
        let response: YTListResponse<YTChannel> = try await send(
            .get, "channels", query: ["part": "snippet", "mine": "true"], requiresAccount: true
        )
        return response.items.first?.profile
    }

    func myPlaylists() async throws -> [Playlist] {
        let items: [YTPlaylist] = try await allPages("playlists", query: [
            "part": "snippet,contentDetails,status",
            "mine": "true",
        ])
        return items.map(\.playlist)
    }

    func entries(inPlaylist playlistID: String) async throws -> [PlaylistEntry] {
        let items: [YTPlaylistItem] = try await allPages("playlistItems", query: [
            "part": "snippet,contentDetails",
            "playlistId": playlistID,
        ])
        // Private and deleted videos come back without details from /videos, which filters them out.
        let tracks = try await videos(ids: items.compactMap(\.videoID))
        let tracksByID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return items.compactMap { item in
            guard let videoID = item.videoID, let track = tracksByID[videoID] else { return nil }
            return PlaylistEntry(id: item.id, track: track)
        }
    }

    func createPlaylist(title: String, privacy: PlaylistPrivacy) async throws -> Playlist {
        let body = YTPlaylistInsert(
            snippet: YTPlaylistInsertSnippet(title: title, description: ""),
            status: YTPrivacyStatus(privacyStatus: privacy.rawValue)
        )
        let playlist: YTPlaylist = try await send(
            .post, "playlists", query: ["part": "snippet,status"], body: body, requiresAccount: true
        )
        return playlist.playlist
    }

    func add(videoID: String, toPlaylist playlistID: String) async throws {
        let body = YTPlaylistItemInsert(snippet: YTPlaylistItemInsertSnippet(
            playlistId: playlistID,
            resourceId: YTResourceID(kind: YTResourceID.videoKind, videoId: videoID)
        ))
        _ = try await data(.post, "playlistItems", query: ["part": "snippet"], body: body, requiresAccount: true)
    }

    /// Renames a playlist. YouTube replaces the whole snippet, so the description goes along
    /// unchanged. Costs 50 quota units.
    func renamePlaylist(_ playlist: Playlist, to title: String) async throws {
        let body = YTPlaylistUpdate(
            id: playlist.id,
            snippet: YTPlaylistInsertSnippet(title: title, description: playlist.summary)
        )
        _ = try await data(.put, "playlists", query: ["part": "snippet"], body: body, requiresAccount: true)
    }

    /// Deletes a playlist from the user's account. Costs 50 quota units.
    func deletePlaylist(id playlistID: String) async throws {
        _ = try await data(.delete, "playlists", query: ["id": playlistID], body: nil, requiresAccount: true)
    }

    func removeEntry(_ entryID: String) async throws {
        _ = try await data(.delete, "playlistItems", query: ["id": entryID], body: nil, requiresAccount: true)
    }

    // MARK: Likes

    /// Whether the user has liked a video. Costs 1 quota unit.
    func isLiked(videoID: String) async throws -> Bool {
        let response: YTRatingResponse = try await send(
            .get, "videos/getRating", query: ["id": videoID], requiresAccount: true
        )
        return response.items.first { $0.videoId == videoID }?.rating == YTVideoRating.like
    }

    /// Likes a video, or takes the like back. Costs 50 quota units.
    func setLiked(_ isLiked: Bool, videoID: String) async throws {
        let rating = isLiked ? YTVideoRating.like : YTVideoRating.none
        _ = try await data(.post, "videos/rate", query: ["id": videoID, "rating": rating], body: nil, requiresAccount: true)
    }

    // MARK: Transport

    private enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

    private func send<Response: Decodable>(
        _ method: HTTPMethod,
        _ path: String,
        query: [String: String],
        body: (any Encodable)? = nil,
        requiresAccount: Bool = false
    ) async throws -> Response {
        let data = try await data(method, path, query: query, body: body, requiresAccount: requiresAccount)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw AppError.decoding
        }
    }

    private func allPages<Item: Decodable & Sendable>(_ path: String, query: [String: String]) async throws -> [Item] {
        var items: [Item] = []
        var pageToken: String?
        var pagesFetched = 0
        repeat {
            var pageQuery = query
            pageQuery["maxResults"] = String(YouTubeAPILimits.maxPageSize)
            pageQuery["pageToken"] = pageToken
            let response: YTListResponse<Item> = try await send(.get, path, query: pageQuery, requiresAccount: true)
            items += response.items
            pageToken = response.nextPageToken
            pagesFetched += 1
        } while pageToken != nil && pagesFetched < YouTubeAPILimits.maxPages
        return items
    }

    private func data(
        _ method: HTTPMethod,
        _ path: String,
        query: [String: String],
        body: (any Encodable)?,
        requiresAccount: Bool,
        isRetry: Bool = false
    ) async throws -> Data {
        var queryItems = query
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: GoogleEndpoint.youtubeAPI.appending(path: path))
        request.httpMethod = method.rawValue

        let accessToken = try await auth.validAccessToken()
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        } else if requiresAccount {
            throw AppError.signInRequired
        } else if let apiKey = config.youtubeAPIKey {
            queryItems.append(URLQueryItem(name: "key", value: apiKey))
            // Required when the key is restricted to iOS apps.
            request.setValue(config.bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        } else {
            throw AppError.missingConfiguration(.youtubeAPIKey)
        }
        request.url = request.url?.appending(queryItems: queryItems)

        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if method == .post {
            // Google rejects a POST that doesn't state a length, even an empty one.
            request.httpBody = Data()
        }

        let (data, response) = try await perform(request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? HTTPStatus.success.lowerBound
        switch statusCode {
        case HTTPStatus.success:
            return data
        case HTTPStatus.unauthorized where accessToken != nil && !isRetry:
            try await auth.refreshAccessToken()
            return try await self.data(
                method, path, query: query, body: body, requiresAccount: requiresAccount, isRetry: true
            )
        default:
            throw AppError(apiStatus: statusCode, body: data, decoder: decoder)
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            // Let cancellation through untouched so callers can ignore it.
            if error.isCancellation { throw error }
            throw AppError(error)
        }
    }
}

// MARK: - MusicCatalog

extension YouTubeAPIClient: MusicCatalog {
    var service: MusicService { .youtube }

    var capabilities: CatalogCapabilities {
        [.likedSongs, .newFromSubscriptions, .recentlyAdded, .createPlaylists, .removeFromPlaylists, .playlistPrivacy, .editPlaylists]
    }

    var isConfigured: Bool { auth.isConfigured }
    var isConnected: Bool { auth.isSignedIn }
    var connectTitle: String { String(localized: "Connect YouTube Account") }

    var connectPrompt: String {
        String(localized: "Connect your YouTube account to see your liked music, your playlists and new releases from channels you subscribe to.")
    }

    var chartDescription: String {
        String(localized: "Most popular music videos in \(config.regionName)")
    }

    func connect(using webAuthenticationSession: WebAuthenticationSession) async throws {
        try await auth.signIn(using: webAuthenticationSession)
    }

    func disconnect() async {
        await auth.signOut()
    }

    func trending() async throws -> [Track] { try await trendingMusic() }
    func playlists() async throws -> [Playlist] { try await myPlaylists() }
    func entries(in playlist: Playlist) async throws -> [PlaylistEntry] { try await entries(inPlaylist: playlist.id) }
    func likedSongs() async throws -> [Track] { try await likedMusic() }

    func add(_ track: Track, to playlist: Playlist) async throws {
        try await add(videoID: track.id, toPlaylist: playlist.id)
    }

    func remove(_ entry: PlaylistEntry, from playlist: Playlist) async throws {
        try await removeEntry(entry.id)
    }

    func rename(_ playlist: Playlist, to title: String) async throws {
        try await renamePlaylist(playlist, to: title)
    }

    func delete(_ playlist: Playlist) async throws {
        try await deletePlaylist(id: playlist.id)
    }

    /// The greeting simply leaves the name out if the channel can't be loaded.
    func profileName() async -> String? {
        let channel = try? await myChannel()
        return channel?.title.split(separator: " ").first.map(String.init)
    }
}

private extension AppError {
    init(apiStatus statusCode: Int, body: Data, decoder: JSONDecoder) {
        let envelope = try? decoder.decode(GoogleAPIErrorEnvelope.self, from: body)
        let message = envelope?.error.message
        let reason = envelope?.error.errors?.first?.reason
        switch reason {
        case "quotaExceeded", "dailyLimitExceeded", "rateLimitExceeded", "userRateLimitExceeded":
            self = .quotaExceeded
        case "keyInvalid", "keyExpired":
            self = .invalidAPIKey
        case "accessNotConfigured":
            self = .apiNotEnabled
        case "youtubeSignupRequired", "channelNotFound":
            self = .channelRequired
        default:
            if message?.localizedCaseInsensitiveContains("API key") == true {
                self = .invalidAPIKey
            } else if statusCode == HTTPStatus.unauthorized {
                self = .sessionExpired
            } else if statusCode == HTTPStatus.forbidden {
                self = .forbidden(message)
            } else if statusCode == HTTPStatus.notFound {
                self = .notFound
            } else {
                self = .server(statusCode: statusCode, message: message)
            }
        }
    }
}
