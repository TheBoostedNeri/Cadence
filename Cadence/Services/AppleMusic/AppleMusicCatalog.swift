// iPhone and iPad only: macOS has no MediaPlayer library, so the Mac app plays YouTube only.
#if os(iOS)
import AuthenticationServices
import MediaPlayer
import Observation
import SwiftUI

/// Apple Music without MusicKit: the catalog comes from Apple's public services and the user's
/// library from MediaPlayer, which only needs the Media & Apple Music permission.
@Observable
final class AppleMusicCatalog: MusicCatalog {
    private(set) var authorization: MPMediaLibraryAuthorizationStatus

    @ObservationIgnored private let config: AppConfig
    @ObservationIgnored private let client: AppleCatalogClient

    init(config: AppConfig, client: AppleCatalogClient = AppleCatalogClient()) {
        self.config = config
        self.client = client
        authorization = MPMediaLibrary.authorizationStatus()
    }

    var service: MusicService { .appleMusic }
    var capabilities: CatalogCapabilities { [.recentlyAdded, .createPlaylists] }
    var isConfigured: Bool { true }
    var isConnected: Bool { authorization == .authorized }
    var connectTitle: String { String(localized: "Allow Apple Music Access") }

    var connectPrompt: String {
        isAccessBlocked
            ? String(localized: "Turn on Media & Apple Music for Cadence in the Settings app to see your library.")
            : String(localized: "Allow access to your Apple Music library to see your playlists and recently added songs.")
    }

    var chartDescription: String {
        String(localized: "Top songs on Apple Music in \(config.regionName)")
    }

    private var isAccessBlocked: Bool { authorization == .denied || authorization == .restricted }
    private var country: String { config.regionCode.lowercased() }

    // MARK: Access

    func connect(using _: WebAuthenticationSession) async throws {
        authorization = MPMediaLibrary.authorizationStatus()
        guard !isAccessBlocked else { throw AppError.appleMusicAccessDenied }
        authorization = await MPMediaLibrary.requestAuthorization()
        guard isConnected else { throw AppError.appleMusicAccessDenied }
    }

    /// Access can only be revoked in the Settings app.
    func disconnect() async {}

    /// Picks up changes the user made in the Settings app.
    func refreshAuthorization() {
        authorization = MPMediaLibrary.authorizationStatus()
    }

    private func requireAccess() throws {
        refreshAuthorization()
        guard isConnected else {
            throw isAccessBlocked ? AppError.appleMusicAccessDenied : AppError.appleMusicAccessNeeded
        }
    }

    // MARK: Catalog

    func trending() async throws -> [Track] {
        try await client.topSongs(country: country)
    }

    func search(_ query: String) async throws -> [Track] {
        try await client.search(query, country: country)
    }

    // MARK: Library

    func playlists() async throws -> [Playlist] {
        try requireAccess()
        let mediaPlaylists = (MPMediaQuery.playlists().collections ?? []).compactMap { $0 as? MPMediaPlaylist }
        // Library artwork is a local image, so cover art comes from each playlist's first catalog song.
        let firstSongIDs = mediaPlaylists.compactMap { $0.items.first(where: Self.isInCatalog)?.playbackStoreID }
        let covers = await catalogDetails(ids: firstSongIDs)
        return mediaPlaylists.map { mediaPlaylist in
            let cover = mediaPlaylist.items.first(where: Self.isInCatalog).flatMap { covers[$0.playbackStoreID] }
            return Self.playlist(from: mediaPlaylist, cover: cover)
        }
    }

    func entries(in playlist: Playlist) async throws -> [PlaylistEntry] {
        try requireAccess()
        guard let mediaPlaylist = Self.mediaPlaylist(withID: playlist.id) else { throw AppError.notFound }
        return await tracks(for: mediaPlaylist.items)
            .enumerated()
            .map { PlaylistEntry(id: "\(playlist.id)-\($0.offset)", track: $0.element) }
    }

    func recentlyAdded(to _: [Playlist]) async throws -> [AddedTrack] {
        try requireAccess()
        let newest = (MPMediaQuery.songs().items ?? [])
            .filter(Self.isInCatalog)
            .sorted { $0.dateAdded > $1.dateAdded }
            .prefix(AppleMusicLimits.recentlyAddedLimit)
        let addedDates = Dictionary(newest.map { ($0.playbackStoreID, $0.dateAdded) }, uniquingKeysWith: max)
        return await tracks(for: Array(newest)).compactMap { track in
            addedDates[track.id].map { AddedTrack(track: track, addedAt: $0) }
        }
    }

    func createPlaylist(title: String, privacy _: PlaylistPrivacy) async throws -> Playlist {
        try requireAccess()
        return try await Self.makePlaylist(named: title)
    }

    func add(_ track: Track, to playlist: Playlist) async throws {
        try requireAccess()
        try await Self.addSong(track.id, toPlaylistWithID: playlist.id)
    }

    func likedSongs() async throws -> [Track] { [] }
    func newFromSubscriptions() async throws -> [Track] { [] }

    func remove(_ entry: PlaylistEntry, from playlist: Playlist) async throws {
        throw AppError.unsupported(String(localized: "Apple Music doesn't let apps remove songs from playlists."))
    }

    func rename(_ playlist: Playlist, to title: String) async throws {
        throw AppError.unsupported(String(localized: "Apple Music doesn't let apps rename playlists."))
    }

    func delete(_ playlist: Playlist) async throws {
        throw AppError.unsupported(String(localized: "Apple Music doesn't let apps delete playlists."))
    }

    func profileName() async -> String? { nil }

    // MARK: Helpers

    /// Only songs from the Apple Music catalog can be played by ID; uploaded files can't.
    private static func isInCatalog(_ item: MPMediaItem) -> Bool {
        !item.playbackStoreID.isEmpty && item.playbackStoreID != "0"
    }

    private func tracks(for items: [MPMediaItem]) async -> [Track] {
        let catalogItems = items.filter(Self.isInCatalog)
        let details = await catalogDetails(ids: catalogItems.map(\.playbackStoreID))
        return catalogItems.map { item in
            let detail = details[item.playbackStoreID]
            return Track(
                id: item.playbackStoreID,
                title: item.title ?? detail?.title ?? "",
                artist: item.artist ?? detail?.artist ?? "",
                artworkURL: detail?.artworkURL,
                largeArtworkURL: detail?.largeArtworkURL,
                duration: item.playbackDuration > 0 ? item.playbackDuration : detail?.duration,
                source: .appleMusic
            )
        }
    }

    /// Catalog artwork and details; a failed lookup only costs artwork, never the list itself.
    private func catalogDetails(ids: [String]) async -> [String: Track] {
        guard !ids.isEmpty, let tracks = try? await client.lookup(ids: ids, country: country) else { return [:] }
        return Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func playlist(from mediaPlaylist: MPMediaPlaylist, cover: Track?) -> Playlist {
        Playlist(
            id: String(mediaPlaylist.persistentID),
            title: mediaPlaylist.name ?? String(localized: "Untitled Playlist"),
            summary: mediaPlaylist.descriptionText ?? "",
            artworkURL: cover?.artworkURL,
            largeArtworkURL: cover?.largeArtworkURL,
            itemCount: mediaPlaylist.count,
            privacy: nil
        )
    }

    // MediaPlayer calls these completion handlers on background threads, so the work happens in
    // nonisolated helpers rather than on the main actor.

    private nonisolated static func mediaPlaylist(withID id: String) -> MPMediaPlaylist? {
        guard let persistentID = MPMediaEntityPersistentID(id) else { return nil }
        let query = MPMediaQuery.playlists()
        query.addFilterPredicate(MPMediaPropertyPredicate(
            value: NSNumber(value: persistentID),
            forProperty: MPMediaPlaylistPropertyPersistentID
        ))
        return query.collections?.first as? MPMediaPlaylist
    }

    private nonisolated static func makePlaylist(named title: String) async throws -> Playlist {
        try await withCheckedThrowingContinuation { continuation in
            MPMediaLibrary.default().getPlaylist(
                with: UUID(),
                creationMetadata: MPMediaPlaylistCreationMetadata(name: title)
            ) { mediaPlaylist, error in
                if let mediaPlaylist {
                    continuation.resume(returning: Playlist(
                        id: String(mediaPlaylist.persistentID),
                        title: mediaPlaylist.name ?? title,
                        summary: "",
                        artworkURL: nil,
                        largeArtworkURL: nil,
                        itemCount: 0,
                        privacy: nil
                    ))
                } else {
                    continuation.resume(throwing: AppError.unknown(error?.localizedDescription ?? ""))
                }
            }
        }
    }

    private nonisolated static func addSong(_ storeID: String, toPlaylistWithID playlistID: String) async throws {
        guard let mediaPlaylist = mediaPlaylist(withID: playlistID) else { throw AppError.notFound }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            mediaPlaylist.addItem(withProductID: storeID) { error in
                if let error {
                    continuation.resume(throwing: AppError.unknown(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
#endif
