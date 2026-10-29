import SwiftUI

/// What's trending on the selected service, then every genre to explore, like Apple Music's
/// Browse. Genres come from Apple's charts and play on the selected service.
struct DiscoverView: View {
    @Environment(ServiceHub.self) private var hub
    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router
    @State private var chart: LoadState<[Track]> = .idle
    @State private var refreshError: AppError?
    @State private var pageWidth: CGFloat = 0
    @State private var isShowingChart = false

    var body: some View {
        NavigationStack(path: router.path(for: .discover)) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxLarge) {
                    trendingSection
                    genresSection
                }
                .padding(.vertical, Spacing.large)
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                pageWidth = width
            }
            .background { Palette.backgroundGradient.ignoresSafeArea() }
            .navigationTitle("Discover")
            .catalogPageDestinations()
            .navigationDestination(for: MusicGenre.self) { genre in
                GenreView(genre: genre)
            }
            .navigationDestination(isPresented: $isShowingChart) {
                TrendingChartView(tracks: chart.value ?? [])
            }
            .refreshable { await loadChart() }
            .task(id: hub.current) {
                // A different service has a different chart.
                if chart.value?.first?.source != hub.current { chart = .idle }
                if chart.value == nil { await loadChart() }
            }
            .errorAlert($refreshError)
        }
    }

    // MARK: Trending

    @ViewBuilder private var trendingSection: some View {
        switch chart {
        case .idle, .loading:
            VStack(alignment: .leading, spacing: Spacing.medium) {
                SectionHeader(title: "Trending Now")
                    .padding(.horizontal, Spacing.large)
                ShelfLoadingView()
            }
        case .failed(let error):
            VStack(alignment: .leading, spacing: Spacing.medium) {
                SectionHeader(title: "Trending Now")
                InlineErrorView(error: error) {
                    Task { await loadChart() }
                }
            }
            .padding(.horizontal, Spacing.large)
        case .loaded(let tracks) where tracks.isEmpty:
            // Some regions have no chart; the genres still work.
            EmptyView()
        case .loaded(let tracks):
            VStack(alignment: .leading, spacing: Spacing.medium) {
                SectionHeader(
                    title: "Trending Now",
                    subtitle: hub.catalog.chartDescription,
                    actionTitle: "See All",
                    action: { isShowingChart = true }
                )
                .padding(.horizontal, Spacing.large)
                SongColumns(tracks: Array(tracks.prefix(Layout.songColumnsShown)), pageWidth: pageWidth) { index, track in
                    SongRow(for: track) {
                        player.play(tracks, startingAt: index)
                    } label: {
                        RankedTrackRow(rank: index + 1, track: track, isCurrent: player.currentTrack?.id == track.id)
                    }
                }
            }
        }
    }

    // MARK: Genres

    private var genresSection: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            SectionHeader(title: "Browse by Genre")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Layout.genreTileMinWidth), spacing: Spacing.medium)],
                spacing: Spacing.medium
            ) {
                ForEach(Array(MusicGenre.all.enumerated()), id: \.element.id) { index, genre in
                    NavigationLink(value: genre) {
                        GenreTile(genre: genre, tint: Palette.genreTints[index % Palette.genreTints.count])
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, Spacing.large)
    }

    private func loadChart() async {
        if let error = await refreshContent($chart, operation: { try await hub.catalog.trending() }) {
            refreshError = error
        }
    }
}

/// A song with its chart position in front.
private struct RankedTrackRow: View {
    let rank: Int
    let track: Track
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: Spacing.medium) {
            Text(rank, format: .number)
                .font(Typography.chartRank)
                .foregroundStyle(Palette.textSecondary)
                .frame(minWidth: Layout.chartRankWidth)
            TrackRow(track: track, isCurrent: isCurrent)
        }
    }
}

/// The whole trending chart, from Trending Now's See All.
private struct TrendingChartView: View {
    let tracks: [Track]

    @Environment(ServiceHub.self) private var hub
    @Environment(PlayerController.self) private var player

    var body: some View {
        SelectableSongList(tracks: tracks, isCurrent: { player.currentTrack?.id == $0.id }) {
            Text(hub.catalog.chartDescription)
        }
        .background { Palette.backgroundGradient.ignoresSafeArea() }
        .navigationTitle("Trending Now")
    }
}

/// A ranked song list with Select, like Apple Music's: picked songs are added to a playlist
/// together. Otherwise each row plays from there, with its ⋯ menu.
private struct SelectableSongList<Header: View>: View {
    let tracks: [Track]
    let isCurrent: (Track) -> Bool
    @ViewBuilder let header: Header

    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router
    @State private var isSelecting = false
    /// Positions rather than songs, since a chart can list the same song twice.
    @State private var selection: Set<Int> = []

    private var isAllSelected: Bool { selection.count == tracks.count }
    private var selectedTracks: [Track] {
        tracks.indices.filter(selection.contains).map { tracks[$0] }
    }

    var body: some View {
        TrackCollection(tracks, id: { index, _ in index }) {
            header
        } row: { index, track in
            if isSelecting {
                selectableRow(index, track)
            } else {
                SongRow(for: track) {
                    player.play(tracks, startingAt: index)
                } label: {
                    RankedTrackRow(rank: index + 1, track: track, isCurrent: isCurrent(track))
                }
            }
        }
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isAllSelected ? "Deselect All" : "Select All") {
                        selection = isAllSelected ? [] : Set(tracks.indices)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: endSelecting)
                }
            } else if !tracks.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Select", systemImage: "checkmark.circle") { isSelecting = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Play All", systemImage: "play.fill") { player.play(tracks) }
                }
            }
        }
        .navigationBarBackButtonHidden(isSelecting)
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                Button {
                    router.addToPlaylist(selectedTracks)
                    endSelecting()
                } label: {
                    Label(
                        selection.isEmpty ? "Add to Playlist" : "Add \(selection.count) to Playlist",
                        systemImage: "text.badge.plus"
                    )
                    .foregroundStyle(Palette.onBrand)
                    .frame(maxWidth: Layout.buttonMaxWidth)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(selection.isEmpty)
                .padding(Spacing.large)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.standard, value: isSelecting)
    }

    private func selectableRow(_ index: Int, _ track: Track) -> some View {
        let isSelected = selection.contains(index)
        return Button {
            if isSelected {
                selection.remove(index)
            } else {
                selection.insert(index)
            }
        } label: {
            HStack(spacing: Spacing.medium) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(Typography.selectionMark)
                    .foregroundStyle(isSelected ? Palette.brand : Palette.textSecondary)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                RankedTrackRow(rank: index + 1, track: track, isCurrent: isCurrent(track))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    private func endSelecting() {
        isSelecting = false
        selection = []
    }
}

/// A colorful tile for a genre, its symbol tucked into the corner, like Apple Music's Browse.
private struct GenreTile: View {
    let genre: MusicGenre
    let tint: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: Radius.large)
                .fill(tint.gradient)
            Image(systemName: genre.systemImage)
                .font(Typography.genreTileSymbol)
                .foregroundStyle(Palette.onPlayer.opacity(Opacity.genreSymbol))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(Spacing.medium)
                .accessibilityHidden(true)
            Text(genre.name)
                .font(Typography.genreTileTitle)
                .foregroundStyle(Palette.onPlayer)
                .lineLimit(Layout.cardTitleLineLimit)
                .padding(Spacing.medium)
        }
        .frame(height: Layout.genreTileHeight)
        .contentShape(.rect(cornerRadius: Radius.large))
        .pointerHover(.lift)
    }
}

/// A genre's best-selling songs from Apple's charts, played on the selected service.
private struct GenreView: View {
    let genre: MusicGenre

    @Environment(CatalogBrowser.self) private var catalog
    @Environment(ServiceHub.self) private var hub
    @Environment(PlayerController.self) private var player
    @State private var songs: LoadState<[Track]> = .idle

    /// On YouTube each song's video is found as it comes up to play.
    private var playableSongs: [Track] {
        CatalogPlayback.tracks(songs.value ?? [], on: hub.current)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { Palette.backgroundGradient.ignoresSafeArea() }
            .navigationTitle(genre.name)
            .task {
                if songs.value == nil { await load() }
            }
    }

    @ViewBuilder private var content: some View {
        switch songs {
        case .idle, .loading:
            LoadingStateView("Finding \(genre.name) songs…")
        case .failed(let error):
            ErrorStateView(error: error) {
                Task { await load() }
            }
        case .loaded(let tracks) where tracks.isEmpty:
            EmptyStateView(
                title: "No Songs Here Yet",
                systemImage: genre.systemImage,
                message: "Apple has no \(genre.name) chart for your region. Try another genre."
            )
        case .loaded:
            let tracks = playableSongs
            SelectableSongList(tracks: tracks, isCurrent: { CatalogPlayback.isCurrent($0, in: player) }) {
                PlayShuffleButtons { shuffled in
                    player.play(shuffled ? tracks.shuffled() : tracks)
                }
                .padding(.vertical, Spacing.small)
            }
            .refreshable { await load() }
        }
    }

    private func load() async {
        await refreshContent($songs) { try await catalog.topSongs(in: genre) }
    }
}

#Preview {
    DiscoverView()
        .appEnvironment(.preview())
}
