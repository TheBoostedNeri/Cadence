import Foundation
import Observation

/// The active service's playlists, shared by Home, the Playlists tab and the "Add to Playlist" sheet.
@Observable
final class LibraryStore {
    private(set) var playlists: LoadState<[Playlist]> = .idle
    /// A refresh failure while playlists are already on screen.
    var refreshError: AppError?

    @ObservationIgnored private let hub: ServiceHub
    /// Finds the YouTube video for a song from Apple's catalog, like those in Discover's genres.
    @ObservationIgnored var matchYouTubeVideo: ((Track) async throws -> Track)?

    init(hub: ServiceHub) {
        self.hub = hub
    }

    func loadPlaylists() async {
        let previous = playlists.value
        if previous == nil { playlists = .loading }
        do {
            playlists = .loaded(try await hub.catalog.playlists())
        } catch {
            if error.isCancellation {
                if previous == nil { playlists = .idle }
            } else if previous == nil {
                playlists = .failed(AppError(error))
            } else {
                refreshError = AppError(error)
            }
        }
    }

    func createPlaylist(title: String, privacy: PlaylistPrivacy) async throws -> Playlist {
        let playlist = try await hub.catalog.createPlaylist(title: title, privacy: privacy)
        if case .loaded(let current) = playlists {
            playlists = .loaded([playlist] + current)
        }
        return playlist
    }

    /// A catalog song waiting for its YouTube video gets it first, which costs a YouTube search
    /// the first time. Throws `noYouTubeMatch` when YouTube has no video for it.
    func add(_ track: Track, to playlist: Playlist) async throws {
        var track = track
        if track.needsYouTubeMatch {
            guard let matchYouTubeVideo else { throw AppError.playback(.noYouTubeMatch) }
            track = try await matchYouTubeVideo(track)
        }
        try await hub.catalog.add(track, to: playlist)
        adjustItemCount(ofPlaylist: playlist.id, by: 1)
    }

    func entries(in playlist: Playlist) async throws -> [PlaylistEntry] {
        try await hub.catalog.entries(in: playlist)
    }

    func remove(_ entry: PlaylistEntry, from playlist: Playlist) async throws {
        try await hub.catalog.remove(entry, from: playlist)
        adjustItemCount(ofPlaylist: playlist.id, by: -1)
    }

    func rename(_ playlist: Playlist, to title: String) async throws {
        try await hub.catalog.rename(playlist, to: title)
        guard case .loaded(var current) = playlists,
              let index = current.firstIndex(where: { $0.id == playlist.id })
        else { return }
        current[index].title = title
        playlists = .loaded(current)
    }

    func delete(_ playlist: Playlist) async throws {
        try await hub.catalog.delete(playlist)
        if case .loaded(let current) = playlists {
            playlists = .loaded(current.filter { $0.id != playlist.id })
        }
    }

    /// The latest copy of `playlist`, such as after a rename.
    func current(_ playlist: Playlist) -> Playlist {
        playlists.value?.first { $0.id == playlist.id } ?? playlist
    }

    func reset() {
        playlists = .idle
        refreshError = nil
    }

    private func adjustItemCount(ofPlaylist playlistID: Playlist.ID, by delta: Int) {
        guard case .loaded(var current) = playlists,
              let index = current.firstIndex(where: { $0.id == playlistID })
        else { return }
        current[index].itemCount = max(0, current[index].itemCount + delta)
        playlists = .loaded(current)
    }
}
