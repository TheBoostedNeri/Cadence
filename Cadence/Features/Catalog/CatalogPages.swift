import SwiftUI

extension View {
    /// Lets "Go to Album" and "Go to Artist" open pages in this tab's navigation stack.
    func catalogPageDestinations() -> some View {
        navigationDestination(for: CatalogPage.self) { page in
            switch page {
            case .album(let track): AlbumView(track: track)
            case .catalogAlbum(let id, let track): AlbumView(track: track, albumID: id)
            case .artist(let track): ArtistView(track: track)
            }
        }
    }
}

/// How songs from a catalog page play.
enum CatalogPlayback {
    /// Apple Music songs play as they are when the page was opened from one. Anywhere else, and
    /// always on the Mac, they play through YouTube, each video found as its song comes up.
    static func tracks(_ catalogTracks: [Track], openedFrom track: Track) -> [Track] {
        tracks(catalogTracks, on: track.source)
    }

    /// Catalog songs as `service` plays them: as they are on Apple Music, otherwise through YouTube.
    static func tracks(_ catalogTracks: [Track], on service: MusicService) -> [Track] {
        #if os(iOS)
        if service == .appleMusic { return catalogTracks }
        #endif
        return catalogTracks.map(\.forYouTubePlayback)
    }

    /// The song playing is this catalog song, whichever service plays it.
    static func isCurrent(_ song: Track, in player: PlayerController) -> Bool {
        song.catalogSongID != nil && player.currentTrack?.catalogSongID == song.catalogSongID
    }
}
