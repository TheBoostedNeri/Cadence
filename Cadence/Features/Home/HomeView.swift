import SwiftData
import SwiftUI

/// Personal shelves when the active service is connected; a connect prompt and a Trending
/// preview otherwise. Shelves the service doesn't support are left out.
/// Each shelf loads and fails on its own, so one problem never blanks the whole screen.
struct HomeView: View {
    @Environment(ServiceHub.self) private var hub
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router
    @Environment(\.isWideLayout) private var isWideLayout
    @State private var liked: LoadState<[Track]> = .idle
    @State private var subscriptionUploads: LoadState<[Track]> = .idle
    @State private var recentlyAdded: LoadState<[AddedTrack]> = .idle
    @State private var isShowingAllRecentlyAdded = false
    @State private var trending: LoadState<[Track]> = .idle
    @State private var firstName: String?
    /// The service the shelves were loaded from; switching services clears them.
    @State private var loadedService: MusicService?
    @State private var refreshError: AppError?

    var body: some View {
        NavigationStack(path: router.path(for: .home)) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxLarge) {
                    if hub.catalog.isConnected {
                        personalContent
                    } else {
                        signedOutContent
                    }
                }
                .padding(.vertical, Spacing.large)
            }
            .background { Palette.backgroundGradient.ignoresSafeArea() }
            .navigationTitle("Home")
            .catalogPageDestinations()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    #if os(iOS)
                    Button("Settings", systemImage: "gearshape") {
                        router.isAccountPresented = true
                    }
                    #else
                    // The Mac opens its standard Settings window (also ⌘,).
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                    #endif
                }
            }
            .navigationDestination(for: Playlist.self) { playlist in
                PlaylistDetailView(playlist: playlist)
            }
            .navigationDestination(isPresented: $isShowingAllRecentlyAdded) {
                RecentlyAddedView(entries: recentlyAdded.value ?? [])
            }
            .refreshable { await load(force: true) }
            .task(id: hub.connectionKey) { await load(force: false) }
            .errorAlert($refreshError)
        }
    }

    // MARK: Signed in

    @ViewBuilder private var personalContent: some View {
        Text(greeting)
            .font(Typography.greeting)
            .padding(.horizontal, Spacing.large)
            .accessibilityAddTraits(.isHeader)

        JumpBackInShelf(service: hub.current)

        if supports(.likedSongs) {
            trackShelf(
                "Liked Music",
                subtitle: String(localized: "Songs you've liked on \(hub.current.name)"),
                state: liked,
                style: .carousel,
                retry: { await loadLiked(force: true) }
            )
        }

        playlistsShelf

        if supports(.recentlyAdded) {
            recentlyAddedShelf
        }

        if supports(.newFromSubscriptions) {
            trackShelf(
                "New From Your Subscriptions",
                subtitle: String(localized: "Latest music from channels you follow"),
                state: subscriptionUploads,
                style: .list,
                retry: { await loadSubscriptionUploads(force: true) }
            )
        }

        if hasNoPersonalContent {
            // A brand-new account has nothing to show yet; keep Home useful in the meantime.
            trendingPreview
        }
    }

    private var playlistsShelf: some View {
        Group {
            switch library.playlists {
            case .idle, .loading:
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    SectionHeader(title: "Your Playlists")
                        .padding(.horizontal, Spacing.large)
                    ShelfLoadingView()
                }
            case .failed(let error):
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    SectionHeader(title: "Your Playlists")
                    InlineErrorView(error: error) {
                        Task { await library.loadPlaylists() }
                    }
                }
                .padding(.horizontal, Spacing.large)
            case .loaded(let playlists) where playlists.isEmpty:
                EmptyView()
            case .loaded(let playlists):
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    SectionHeader(title: "Your Playlists", actionTitle: "See All") {
                        router.selectedTab = .playlists
                    }
                    .padding(.horizontal, Spacing.large)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: Spacing.large) {
                            ForEach(playlists) { playlist in
                                NavigationLink(value: playlist) {
                                    PlaylistCard(playlist: playlist)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .contentMargins(.horizontal, Spacing.large, for: .scrollContent)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    /// The newest songs across the user's playlists, with how long ago each was added.
    @ViewBuilder private var recentlyAddedShelf: some View {
        switch recentlyAdded {
        case .idle, .loading:
            VStack(alignment: .leading, spacing: Spacing.medium) {
                SectionHeader(title: "Recently Added")
                    .padding(.horizontal, Spacing.large)
                ShelfLoadingView()
            }
        case .failed(let error):
            VStack(alignment: .leading, spacing: Spacing.medium) {
                SectionHeader(title: "Recently Added")
                InlineErrorView(error: error) {
                    Task { await loadRecentlyAdded(force: true) }
                }
            }
            .padding(.horizontal, Spacing.large)
        case .loaded(let entries) where entries.isEmpty:
            EmptyView()
        case .loaded(let entries):
            let tracks = entries.map(\.track)
            VStack(alignment: .leading, spacing: Spacing.medium) {
                // "Show All" only appears when the shelf is hiding some songs.
                SectionHeader(
                    title: "Recently Added",
                    subtitle: hub.current == .appleMusic
                        ? String(localized: "New in your library")
                        : String(localized: "New in your playlists"),
                    actionTitle: "Show All",
                    action: entries.count > HomeContent.listShelfRows ? { isShowingAllRecentlyAdded = true } : nil
                )
                .padding(.horizontal, Spacing.large)

                LazyVGrid(columns: GridColumns.tracks, spacing: Spacing.medium) {
                    ForEach(Array(entries.prefix(HomeContent.listShelfRows).enumerated()), id: \.element.id) { index, entry in
                        SongRow(for: entry.track) {
                            player.play(tracks, startingAt: index)
                        } label: {
                            TrackRow(track: entry.track, isCurrent: player.currentTrack?.id == entry.track.id) {
                                Text(entry.addedAt, format: .relative(presentation: .named))
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                        .pointerHover(.highlight)
                    }
                }
                .padding(.horizontal, Spacing.large)
            }
        }
    }

    private func supports(_ capability: CatalogCapabilities) -> Bool {
        hub.catalog.capabilities.contains(capability)
    }

    /// Whether every shelf the service supports has finished loading with nothing in it.
    private var hasNoPersonalContent: Bool {
        func isEmpty<Value: Collection>(_ state: LoadState<Value>, _ capability: CatalogCapabilities) -> Bool {
            !supports(capability) || state.value?.isEmpty == true
        }
        return isEmpty(liked, .likedSongs)
            && isEmpty(subscriptionUploads, .newFromSubscriptions)
            && isEmpty(recentlyAdded, .recentlyAdded)
            && library.playlists.value?.isEmpty == true
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let salutation = switch hour {
        case HomeContent.morningStartHour..<HomeContent.afternoonStartHour: String(localized: "Good morning")
        case HomeContent.afternoonStartHour..<HomeContent.eveningStartHour: String(localized: "Good afternoon")
        default: String(localized: "Good evening")
        }
        guard let firstName else { return salutation }
        return String(localized: "\(salutation), \(firstName)")
    }

    // MARK: Signed out

    @ViewBuilder private var signedOutContent: some View {
        JumpBackInShelf(service: hub.current)

        VStack(alignment: .leading, spacing: Spacing.medium) {
            Label("Make Home Yours", systemImage: "sparkles")
                .font(Typography.headline)
            Text(hub.catalog.connectPrompt)
                .font(Typography.footnote)
                .foregroundStyle(Palette.textSecondary)
            ConnectAccountButton()
                // A full-width button would stretch across the whole iPad screen.
                .frame(maxWidth: isWideLayout ? Layout.buttonMaxWidth : .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.large)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.large))
        .padding(.horizontal, Spacing.large)

        trendingPreview
    }

    // MARK: Shared shelves


    @ViewBuilder private var trendingPreview: some View {
        Group {
            // Without an API key the connect prompt already explains what's missing.
            if case .failed(let error) = trending, error.offersAccountConnection {
                EmptyView()
            } else {
                trackShelf(
                    "Trending Now",
                    subtitle: hub.catalog.chartDescription,
                    state: trending.map { Array($0.prefix(HomeContent.trendingPreviewCount)) },
                    style: .carousel,
                    actionTitle: "See All",
                    action: { _ in router.selectedTab = .discover },
                    retry: { await loadTrending(force: true) }
                )
            }
        }
        .task {
            await loadTrending(force: false)
        }
    }

    private enum ShelfStyle {
        case carousel
        case list
    }

    /// A titled shelf of tracks. Empty shelves disappear; failures show an inline error.
    /// The header action defaults to playing every track in the shelf.
    @ViewBuilder
    private func trackShelf(
        _ title: LocalizedStringKey,
        subtitle: String? = nil,
        state: LoadState<[Track]>,
        style: ShelfStyle,
        actionTitle: LocalizedStringKey = "Play All",
        action: (([Track]) -> Void)? = nil,
        retry: @escaping () async -> Void
    ) -> some View {
        switch state {
        case .idle, .loading:
            VStack(alignment: .leading, spacing: Spacing.medium) {
                SectionHeader(title: title, subtitle: subtitle)
                    .padding(.horizontal, Spacing.large)
                ShelfLoadingView()
            }
        case .failed(let error):
            VStack(alignment: .leading, spacing: Spacing.medium) {
                SectionHeader(title: title, subtitle: subtitle)
                InlineErrorView(error: error) {
                    Task { await retry() }
                }
            }
            .padding(.horizontal, Spacing.large)
        case .loaded(let tracks) where tracks.isEmpty:
            EmptyView()
        case .loaded(let tracks):
            VStack(alignment: .leading, spacing: Spacing.medium) {
                SectionHeader(title: title, subtitle: subtitle, actionTitle: actionTitle) {
                    if let action { action(tracks) } else { player.play(tracks) }
                }
                .padding(.horizontal, Spacing.large)

                switch style {
                case .carousel:
                    TrackCarousel(tracks: tracks)
                case .list:
                    LazyVGrid(columns: GridColumns.tracks, spacing: Spacing.medium) {
                        ForEach(Array(tracks.prefix(HomeContent.listShelfRows).enumerated()), id: \.offset) { index, track in
                            SongRow(for: track) {
                                player.play(tracks, startingAt: index)
                            } label: {
                                TrackRow(track: track, isCurrent: player.currentTrack?.id == track.id)
                            }
                            .pointerHover(.highlight)
                        }
                    }
                    .padding(.horizontal, Spacing.large)
                }
            }
        }
    }

    // MARK: Loading

    private func load(force: Bool) async {
        if loadedService != hub.current {
            loadedService = hub.current
            liked = .idle
            subscriptionUploads = .idle
            recentlyAdded = .idle
            trending = .idle
            firstName = nil
        }
        if hub.catalog.isConnected {
            async let likedLoad: Void = loadLiked(force: force)
            async let uploadsLoad: Void = loadSubscriptionUploads(force: force)
            async let profileLoad: Void = loadFirstName(force: force)
            // Recently Added reads the playlists, so it waits for them.
            await loadPlaylists(force: force)
            await loadRecentlyAdded(force: force)
            _ = await (likedLoad, uploadsLoad, profileLoad)
        } else {
            liked = .idle
            subscriptionUploads = .idle
            recentlyAdded = .idle
            firstName = nil
            // The Trending shelf loads itself when it appears; only a pull-to-refresh reloads it here.
            if force { await loadTrending(force: true) }
        }
    }

    private func loadLiked(force: Bool) async {
        guard supports(.likedSongs), force || liked.value == nil else { return }
        if let error = await refreshContent($liked, operation: { try await hub.catalog.likedSongs() }) {
            refreshError = error
        }
    }

    private func loadSubscriptionUploads(force: Bool) async {
        guard supports(.newFromSubscriptions), force || subscriptionUploads.value == nil else { return }
        if let error = await refreshContent($subscriptionUploads, operation: { try await hub.catalog.newFromSubscriptions() }) {
            refreshError = error
        }
    }

    private func loadPlaylists(force: Bool) async {
        guard force || library.playlists.value == nil else { return }
        await library.loadPlaylists()
    }

    private func loadRecentlyAdded(force: Bool) async {
        guard supports(.recentlyAdded), force || recentlyAdded.value == nil else { return }
        // A playlist problem already shows on the playlists shelf, so this one just stays hidden.
        let playlists = library.playlists.value ?? []
        guard hub.current == .appleMusic || !playlists.isEmpty else {
            recentlyAdded = .loaded([])
            return
        }
        if let error = await refreshContent($recentlyAdded, operation: { try await hub.catalog.recentlyAdded(to: playlists) }) {
            refreshError = error
        }
    }

    private func loadTrending(force: Bool) async {
        guard force || trending.value == nil else { return }
        if let error = await refreshContent($trending, operation: { try await hub.catalog.trending() }) {
            refreshError = error
        }
    }

    private func loadFirstName(force: Bool) async {
        guard force || firstName == nil else { return }
        firstName = await hub.catalog.profileName()
    }

}

/// The latest songs played on the selected service; hidden until there are some.
private struct JumpBackInShelf: View {
    @Query private var recentPlays: [RecentPlay]

    init(service: MusicService) {
        let source = service.rawValue
        var descriptor = FetchDescriptor<RecentPlay>(
            predicate: #Predicate { $0.source == source },
            sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        )
        descriptor.fetchLimit = HomeContent.recentsLimit
        _recentPlays = Query(descriptor)
    }

    var body: some View {
        if !recentPlays.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                SectionHeader(title: "Jump Back In")
                    .padding(.horizontal, Spacing.large)
                TrackCarousel(tracks: recentPlays.map(\.track))
            }
        }
    }
}

private enum HomeContent {
    static let recentsLimit = 12
    static let trendingPreviewCount = 10
    static let listShelfRows = 8
    static let morningStartHour = 5
    static let afternoonStartHour = 12
    static let eveningStartHour = 17
}

#Preview {
    HomeView()
        .appEnvironment(.preview())
}
