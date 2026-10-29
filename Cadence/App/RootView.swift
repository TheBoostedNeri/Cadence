import SwiftUI

struct RootView: View {
    @AppStorage(StorageKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    var body: some View {
        ZStack {
            if hasCompletedOnboarding {
                MainTabView()
                    .transition(.opacity)
            } else {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.standard, value: hasCompletedOnboarding)
    }
}

struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PlayerController.self) private var player
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isWideLayout) private var isWideLayout
    @Environment(ServiceHub.self) private var hub
    @Environment(LibraryStore.self) private var library
    @AppStorage(StorageKey.youtubeBackgroundPlay) private var isYouTubeBackgroundPlayEnabled = false
    @Namespace private var nowPlayingTransition

    #if os(macOS)
    /// Mac windows show Now Playing in a panel beside the app instead of covering it, so people
    /// can keep browsing while it plays (and YouTube's video stays visible). iPhone and iPad
    /// cover the app with it, as Apple Music does.
    private var isPanelOpen: Bool { player.isNowPlayingPresented }
    #endif

    var body: some View {
        @Bindable var router = router

        windowContent
        // The sidebar of the Mac and iPad lists every playlist by name, so they load with the
        // window. The iPhone has no sidebar, so it waits for the Playlists tab.
        .task(id: SidebarLibrary(service: hub.current, isConnected: hub.catalog.isConnected, hasSidebar: isWideLayout)) {
            if isWideLayout && hub.catalog.isConnected && library.playlists.value == nil {
                await library.loadPlaylists()
            }
        }
        .onChange(of: library.playlists.value?.map(\.id)) { _, ids in
            // A deleted playlist, or one from another service, can't stay selected.
            if case .playlist(let id) = router.selectedTab, ids?.contains(id) != true {
                router.selectedTab = .playlists
            }
        }
        #if os(iOS)
        .onChange(of: isWideLayout) { _, isWide in
            // A narrowed iPad window swaps the sidebar for the tab bar, which lists no playlists.
            if !isWide, case .playlist = router.selectedTab {
                router.selectedTab = .playlists
            }
        }
        #endif
        #if os(iOS)
        // Full screen, status bar included, like Apple Music. The zoom from the mini player also
        // gives it the swipe down to close.
        .fullScreenCover(
            isPresented: Binding(
                get: { player.isNowPlayingPresented },
                set: { player.isNowPlayingPresented = $0 }
            ),
            onDismiss: {
                // Reopened before the dismissal finished, it's still showing.
                if !player.isNowPlayingPresented { player.handleNowPlayingDismissed() }
            }
        ) {
            NowPlayingView()
                .navigationTransition(.zoom(sourceID: NowPlayingTransition.sourceID, in: nowPlayingTransition))
        }
        #else
        .onChange(of: player.isNowPlayingPresented) { _, isPresented in
            // The full-screen player reports its own dismissal; the panel is reported here.
            if !isPresented { player.handleNowPlayingDismissed() }
        }
        #endif
        #if os(iOS)
        // The Mac shows Settings in its own window instead.
        .sheet(isPresented: $router.isAccountPresented) {
            AccountView()
        }
        #endif
        .addToPlaylistSheet(isActive: !player.isNowPlayingPresented)
        .background(alignment: .bottomLeading) {
            // The YouTube player lives here whenever Now Playing isn't showing a music video:
            // songs show their artwork there instead, and Now Playing may be closed. Moving it
            // makes WebKit pause, which `webViewDidMove` resumes. It's tucked into a corner, away
            // from the content, and takes no clicks or taps.
            if !player.showsVideoInNowPlaying {
                YouTubePlayerView(webView: player.webView, onAttach: { player.webViewDidMove() })
                    .frame(width: Layout.hiddenPlayerSide, height: Layout.hiddenPlayerSide)
                    .opacity(Opacity.hiddenPlayer)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: isYouTubeBackgroundPlayEnabled) {
            player.backgroundPlaySettingChanged()
        }
        #if os(iOS)
        // On the Mac, watching the paths here stops every tab but the one shown at launch from
        // opening pages (a SwiftUI quirk), and Now Playing is always the panel there anyway.
        .onChange(of: router.paths) {
            // "Go to Album" and "Go to Artist" open in the tab, so the full-screen player makes way.
            player.isNowPlayingPresented = false
        }
        #endif
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: player.handleAppDidBecomeActive()
            case .background: player.handleAppDidEnterBackground()
            default: break
            }
        }
    }

    /// The Mac's Now Playing panel is a plain column rather than an inspector: the inspector tries
    /// to grow the window as it opens, and near a screen edge gives up partway, shoving the sidebar
    /// sideways until the animation ends. The column just narrows the content beside it.
    @ViewBuilder private var windowContent: some View {
        #if os(macOS)
        HStack(spacing: Spacing.none) {
            tabs
            if isPanelOpen {
                NowPlayingView(presentation: .sidePanel)
                    .frame(width: Layout.nowPlayingPanelWidth)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(Motion.standard, value: isPanelOpen)
        #else
        tabs
        #endif
    }

    @ViewBuilder private var tabs: some View {
        #if os(iOS)
        phoneAndPadTabs
        #else
        macTabs
        #endif
    }

    #if os(iOS)
    private var phoneAndPadTabs: some View {
        @Bindable var router = router

        return TabView(selection: $router.selectedTab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                HomeView()
            }
            Tab("Discover", systemImage: "square.grid.2x2", value: AppTab.discover) {
                DiscoverView()
            }
            Tab("Playlists", systemImage: "music.note.list", value: AppTab.playlists) {
                PlaylistsView()
            }
            Tab("Recents", systemImage: "clock.arrow.circlepath", value: AppTab.recents) {
                RecentsView()
            }
            Tab(value: AppTab.search, role: .search) {
                SearchView()
            }
            // Like Apple Music on iPad: every playlist by name in the sidebar. The tab bar
            // keeps to the five tabs above.
            if !sidebarPlaylists.isEmpty {
                TabSection("Your Playlists") {
                    ForEach(sidebarPlaylists) { playlist in
                        Tab(playlist.title, systemImage: "music.note.list", value: AppTab.playlist(playlist.id)) {
                            SidebarPlaylistView(playlist: playlist)
                        }
                        .defaultVisibility(.hidden, for: .tabBar)
                    }
                }
                .defaultVisibility(.hidden, for: .tabBar)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .miniPlayerAccessory(transition: nowPlayingTransition)
    }
    #else
    /// Apple Music's sidebar: search at the top, then the service, the library, and every
    /// playlist by name. Each page gets the floating player bar, so it covers the content and
    /// not the sidebar.
    private var macTabs: some View {
        @Bindable var router = router
        let playlists = sidebarPlaylists

        return TabView(selection: $router.selectedTab) {
            Tab(value: AppTab.search, role: .search) {
                SearchView()
                    .macPlayerBar()
            }
            TabSection(hub.current.name) {
                Tab("Home", systemImage: "house", value: AppTab.home) {
                    HomeView()
                        .macPlayerBar()
                }
                Tab("Discover", systemImage: "square.grid.2x2", value: AppTab.discover) {
                    DiscoverView()
                        .macPlayerBar()
                }
            }
            TabSection("Library") {
                Tab("Recently Played", systemImage: "clock", value: AppTab.recents) {
                    RecentsView()
                        .macPlayerBar()
                }
            }
            TabSection("Playlists") {
                Tab("All Playlists", systemImage: "square.grid.2x2", value: AppTab.playlists) {
                    PlaylistsView()
                        .macPlayerBar()
                }
                ForEach(playlists) { playlist in
                    Tab(playlist.title, systemImage: "music.note.list", value: AppTab.playlist(playlist.id)) {
                        SidebarPlaylistView(playlist: playlist)
                            .macPlayerBar()
                    }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
    #endif

    /// The playlists listed by name in the sidebar.
    private var sidebarPlaylists: [Playlist] {
        hub.catalog.isConnected ? library.playlists.value ?? [] : []
    }
}

/// What the sidebar's playlists depend on.
private struct SidebarLibrary: Hashable {
    let service: MusicService
    let isConnected: Bool
    let hasSidebar: Bool
}

/// A playlist picked in the sidebar, with its own navigation stack.
private struct SidebarPlaylistView: View {
    let playlist: Playlist
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack(path: router.path(for: .playlist(playlist.id))) {
            PlaylistDetailView(playlist: playlist)
                .catalogPageDestinations()
        }
    }
}

private enum NowPlayingTransition {
    static let sourceID = "now-playing"
}

#if os(iOS)
private extension View {
    /// The mini player in the tab bar's bottom accessory.
    func miniPlayerAccessory(transition: Namespace.ID) -> some View {
        tabViewBottomAccessory {
            MiniPlayerView()
                .matchedTransitionSource(id: NowPlayingTransition.sourceID, in: transition)
        }
    }
}
#endif

#Preview {
    RootView()
        .appEnvironment(.preview())
}
