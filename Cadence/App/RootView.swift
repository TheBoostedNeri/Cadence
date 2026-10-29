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
    #if os(macOS)
    @Environment(ServiceHub.self) private var hub
    @Environment(LibraryStore.self) private var library
    #endif
    @AppStorage(StorageKey.youtubeBackgroundPlay) private var isYouTubeBackgroundPlayEnabled = false
    @Namespace private var nowPlayingTransition

    /// Wide windows, like iPad and every Mac window, show Now Playing in a panel beside the app
    /// instead of covering it, so people can keep browsing while it plays (and YouTube's
    /// video stays visible).
    private var showsNowPlayingAsPanel: Bool { isWideLayout }
    private var isPanelOpen: Bool { showsNowPlayingAsPanel && player.isNowPlayingPresented }

    var body: some View {
        @Bindable var router = router

        windowContent
        #if os(macOS)
        // The sidebar lists every playlist by name, so they load with the window.
        .task(id: SidebarLibrary(service: hub.current, isConnected: hub.catalog.isConnected)) {
            if hub.catalog.isConnected && library.playlists.value == nil {
                await library.loadPlaylists()
            }
        }
        .onChange(of: library.playlists.value?.map(\.id)) { _, ids in
            // A deleted playlist, or one from another service, can't stay selected.
            if case .playlist(let id) = router.selectedTab, ids?.contains(id) != true {
                router.selectedTab = .playlists
            }
        }
        #endif
        #if os(iOS)
        // Full screen, status bar included, like Apple Music. The zoom from the mini player also
        // gives it the swipe down to close.
        .fullScreenCover(
            isPresented: Binding(
                get: { player.isNowPlayingPresented && !showsNowPlayingAsPanel },
                set: { player.isNowPlayingPresented = $0 }
            ),
            onDismiss: {
                // The window may have widened, moving Now Playing into the panel instead.
                if !player.isNowPlayingPresented { player.handleNowPlayingDismissed() }
            }
        ) {
            NowPlayingView()
                .navigationTransition(.zoom(sourceID: NowPlayingTransition.sourceID, in: nowPlayingTransition))
        }
        #endif
        .onChange(of: player.isNowPlayingPresented) { _, isPresented in
            // The full-screen player reports its own dismissal; the panel is reported here.
            if !isPresented && showsNowPlayingAsPanel { player.handleNowPlayingDismissed() }
        }
        #if os(iOS)
        // The Mac shows Settings in its own window instead.
        .sheet(isPresented: $router.isAccountPresented) {
            AccountView()
        }
        #endif
        .addToPlaylistSheet(isActive: !player.isNowPlayingPresented)
        .background(alignment: .bottomLeading) {
            // With background play on, the YouTube player lives here permanently and is never
            // moved: moving it off screen, even for a moment, makes WebKit pause it. It's tucked
            // into a corner, away from the content, and takes no clicks or taps.
            if isYouTubeBackgroundPlayEnabled {
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
        .onChange(of: router.paths) {
            // "Go to Album" and "Go to Artist" open in the tab, so the full-screen player makes
            // way; the panel stays.
            if !showsNowPlayingAsPanel { player.isNowPlayingPresented = false }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: player.handleAppDidBecomeActive()
            case .background: player.handleAppDidEnterBackground()
            default: break
            }
        }
    }

    /// A plain column rather than an inspector, on both platforms. On iPad the inspector keeps its
    /// own open state and reopens itself after the window narrows and widens; on the Mac it tries to
    /// grow the window as it opens, and near a screen edge gives up partway, shoving the sidebar
    /// sideways until the animation ends. The column just narrows the content beside it.
    private var windowContent: some View {
        HStack(spacing: Spacing.none) {
            tabs
            if isPanelOpen {
                NowPlayingView(presentation: panelPresentation)
                    .frame(width: Layout.nowPlayingPanelWidth)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(Motion.standard, value: isPanelOpen)
    }

    private var panelPresentation: NowPlayingView.Presentation {
        #if os(macOS)
        .sidePanel
        #else
        .panel
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
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        // The panel has its own controls, so the mini player steps aside while it's open.
        .miniPlayerAccessory(isEnabled: !isPanelOpen, transition: nowPlayingTransition)
    }
    #else
    /// Apple Music's sidebar: search at the top, then the service, the library, and every
    /// playlist by name. Each page gets the floating player bar, so it covers the content and
    /// not the sidebar.
    private var macTabs: some View {
        @Bindable var router = router
        let playlists = hub.catalog.isConnected ? library.playlists.value ?? [] : []

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
}

#if os(macOS)
/// What the sidebar's playlists depend on.
private struct SidebarLibrary: Hashable {
    let service: MusicService
    let isConnected: Bool
}

/// A playlist picked in the Mac sidebar, with its own navigation stack.
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
#endif

private enum NowPlayingTransition {
    static let sourceID = "now-playing"
}

#if os(iOS)
private extension View {
    /// The mini player in the tab bar's bottom accessory. Hiding it needs iOS 26.1; on 26.0
    /// it always shows.
    @ViewBuilder
    func miniPlayerAccessory(isEnabled: Bool, transition: Namespace.ID) -> some View {
        if #available(iOS 26.1, *) {
            tabViewBottomAccessory(isEnabled: isEnabled) {
                MiniPlayerView()
                    .matchedTransitionSource(id: NowPlayingTransition.sourceID, in: transition)
            }
        } else {
            tabViewBottomAccessory {
                MiniPlayerView()
                    .matchedTransitionSource(id: NowPlayingTransition.sourceID, in: transition)
            }
        }
    }
}
#endif

#Preview {
    RootView()
        .appEnvironment(.preview())
}
