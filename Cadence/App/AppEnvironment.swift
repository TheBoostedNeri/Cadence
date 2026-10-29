import SwiftData
import SwiftUI

/// Creates the app's long-lived services once and injects them into the SwiftUI environment.
final class AppEnvironment {
    let auth: GoogleAuthService
    let api: YouTubeAPIClient
    #if os(iOS)
    let appleMusic: AppleMusicCatalog
    #endif
    let hub: ServiceHub
    let library: LibraryStore
    let player: PlayerController
    let lyrics: LyricsService
    let catalogBrowser: CatalogBrowser
    let likes: YouTubeLikes
    let router: AppRouter
    let modelContainer: ModelContainer

    init(config: AppConfig, modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        auth = GoogleAuthService(config: config)
        api = YouTubeAPIClient(config: config, auth: auth)
        #if os(iOS)
        appleMusic = AppleMusicCatalog(config: config)
        hub = ServiceHub(youtube: api, appleMusic: appleMusic)
        #else
        hub = ServiceHub(youtube: api)
        #endif
        library = LibraryStore(hub: hub)
        router = AppRouter()
        player = PlayerController(config: config)
        lyrics = LyricsService()
        catalogBrowser = CatalogBrowser(config: config)
        likes = YouTubeLikes(api: api, auth: auth)

        let matcher = YouTubeMatcher(api: api)
        player.matchYouTubeVideo = { track in
            try await matcher.match(track)
        }
        let versions = SongVersions(api: api)
        player.findOtherVersion = { track, wantsVideo in
            try await versions.otherVersion(of: track, wantsVideo: wantsVideo)
        }
        let catalogBrowser = catalogBrowser
        player.findAutoplayTracks = { track in
            try await catalogBrowser.autoplayTracks(after: track)
        }

        let library = library
        // Songs from Apple's catalog get their YouTube video before they're added to a playlist.
        library.matchYouTubeVideo = { track in
            try await matcher.match(track)
        }
        hub.onServiceChanged = {
            library.reset()
        }

        let recents = RecentsStore(context: modelContainer.mainContext)
        player.onTrackStarted = { track in
            recents.record(track)
        }
    }

    static func live() -> AppEnvironment {
        // Before anything downloads, so every response can be kept.
        URLCache.shared = URLCache(
            memoryCapacity: NetworkCache.memoryCapacity,
            diskCapacity: NetworkCache.diskCapacity
        )
        return AppEnvironment(config: .load(), modelContainer: .recents(inMemory: false))
    }

    static func preview() -> AppEnvironment {
        AppEnvironment(config: .load(), modelContainer: .recents(inMemory: true))
    }
}

/// App-wide navigation state.
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var isAccountPresented = false
    /// Songs waiting for the "Add to Playlist" sheet: one from a song's menu, or several picked
    /// with Select.
    var pendingPlaylistAddition: PlaylistAddition?
    /// Each tab's navigation stack, so "Go to Album" and "Go to Artist" can open pages in it.
    var paths: [AppTab: NavigationPath] = [:]

    func path(for tab: AppTab) -> Binding<NavigationPath> {
        Binding(
            get: { self.paths[tab] ?? NavigationPath() },
            set: { self.paths[tab] = $0 }
        )
    }

    func addToPlaylist(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        pendingPlaylistAddition = PlaylistAddition(tracks: tracks)
    }

    /// Opens the album `track` is from in the tab on screen.
    func showAlbum(for track: Track) {
        paths[selectedTab, default: NavigationPath()].append(CatalogPage.album(track))
    }

    /// Opens an album picked from an artist's page. `track` is the song the artist was opened from,
    /// which decides how the album plays.
    func showAlbum(id: String, openedFrom track: Track) {
        paths[selectedTab, default: NavigationPath()].append(CatalogPage.catalogAlbum(id: id, openedFrom: track))
    }

    /// Opens the artist of `track` in the tab on screen.
    func showArtist(for track: Track) {
        paths[selectedTab, default: NavigationPath()].append(CatalogPage.artist(track))
    }
}

struct PlaylistAddition: Identifiable {
    let id = UUID()
    let tracks: [Track]
}

/// A catalog page, opened from a song.
enum CatalogPage: Hashable {
    /// The album a song is from.
    case album(Track)
    /// An album by its catalog ID, and the song its artist was opened from.
    case catalogAlbum(id: String, openedFrom: Track)
    case artist(Track)
}

enum AppTab: Hashable {
    case home
    case discover
    case playlists
    case recents
    case search
    /// One of the user's playlists, listed by name in the sidebar on the Mac and iPad.
    case playlist(Playlist.ID)
}

enum StorageKey {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let lyricsOffsets = "lyricsOffsets"
    static let wordByWordLyrics = "experimental.wordByWordLyrics"
    static let musicService = "musicService"
    static let youtubeBackgroundPlay = "experimental.youtubeBackgroundPlay"
    static let youtubeMatches = "youtubeMatches"
    static let songVersions = "songVersions"
    static let playerVolume = "playerVolume"
    static let sidePanelMode = "sidePanelMode"
    static let autoplay = "autoplay"
}

extension View {
    func appEnvironment(_ environment: AppEnvironment) -> some View {
        self
            .environment(environment.auth)
            .environment(environment.api)
            #if os(iOS)
            .environment(environment.appleMusic)
            #endif
            .environment(environment.hub)
            .environment(environment.library)
            .environment(environment.player)
            .environment(environment.lyrics)
            .environment(environment.catalogBrowser)
            .environment(environment.likes)
            .environment(environment.router)
            .modelContainer(environment.modelContainer)
    }
}
