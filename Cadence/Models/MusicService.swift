import AuthenticationServices
import Foundation
import SwiftUI

/// The streaming services Cadence can browse and play from. One is active at a time.
nonisolated enum MusicService: String, CaseIterable, Identifiable, Codable, Sendable {
    case youtube
    case appleMusic
    case spotify

    var id: String { rawValue }

    var name: String {
        switch self {
        case .youtube: String(localized: "YouTube Music")
        case .appleMusic: String(localized: "Apple Music")
        case .spotify: String(localized: "Spotify")
        }
    }

    /// The service's own app, for "Open in …".
    var appName: String {
        switch self {
        case .youtube: String(localized: "YouTube")
        case .appleMusic: String(localized: "Music")
        case .spotify: String(localized: "Spotify")
        }
    }

    var systemImage: String {
        switch self {
        case .youtube: "play.rectangle.fill"
        case .appleMusic: "music.note"
        case .spotify: "waveform"
        }
    }

    var summary: String {
        switch self {
        case .youtube: String(localized: "Music videos, charts and your YouTube playlists.")
        case .appleMusic: String(localized: "Your Apple Music library and catalog, with background play.")
        case .spotify: String(localized: "Your Spotify library, played through the Spotify app.")
        }
    }

    var isRecommended: Bool { self == .youtube }

    var isAvailable: Bool { unavailableReason == nil }

    /// Why the service can't be picked here: Spotify needs its SDK and a developer app, and the
    /// Apple Music library and player APIs don't exist on macOS.
    var unavailableReason: String? {
        switch self {
        case .youtube: nil
        case .appleMusic:
            #if os(iOS)
            nil
            #else
            String(localized: "iPhone & iPad Only")
            #endif
        case .spotify: String(localized: "Needs Setup")
        }
    }
}

/// Features a service's catalog supports, so screens can hide what doesn't apply.
nonisolated struct CatalogCapabilities: OptionSet, Sendable {
    let rawValue: Int

    static let likedSongs = CatalogCapabilities(rawValue: 1 << 0)
    static let newFromSubscriptions = CatalogCapabilities(rawValue: 1 << 1)
    static let recentlyAdded = CatalogCapabilities(rawValue: 1 << 2)
    static let createPlaylists = CatalogCapabilities(rawValue: 1 << 3)
    static let removeFromPlaylists = CatalogCapabilities(rawValue: 1 << 4)
    static let playlistPrivacy = CatalogCapabilities(rawValue: 1 << 5)
    /// Renaming and deleting the user's playlists.
    static let editPlaylists = CatalogCapabilities(rawValue: 1 << 6)
}

/// Browsing, search and library access for one service.
protocol MusicCatalog: AnyObject {
    var service: MusicService { get }
    var capabilities: CatalogCapabilities { get }

    /// Whether the build has what the service needs (keys, client IDs).
    var isConfigured: Bool { get }
    /// Whether the user's library is reachable (signed in, or access granted).
    var isConnected: Bool { get }
    var connectTitle: String { get }
    /// Why connecting is worth it, shown wherever the library is needed.
    var connectPrompt: String { get }
    /// Shown under the chart, e.g. "Most popular music videos in Netherlands".
    var chartDescription: String { get }

    func connect(using webAuthenticationSession: WebAuthenticationSession) async throws
    func disconnect() async

    func trending() async throws -> [Track]
    func search(_ query: String) async throws -> [Track]
    func playlists() async throws -> [Playlist]
    func entries(in playlist: Playlist) async throws -> [PlaylistEntry]
    func likedSongs() async throws -> [Track]
    func newFromSubscriptions() async throws -> [Track]
    func recentlyAdded(to playlists: [Playlist]) async throws -> [AddedTrack]
    func createPlaylist(title: String, privacy: PlaylistPrivacy) async throws -> Playlist
    func add(_ track: Track, to playlist: Playlist) async throws
    func remove(_ entry: PlaylistEntry, from playlist: Playlist) async throws
    func rename(_ playlist: Playlist, to title: String) async throws
    func delete(_ playlist: Playlist) async throws
    /// The user's first name for Home's greeting, if the service knows it.
    func profileName() async -> String?
}
