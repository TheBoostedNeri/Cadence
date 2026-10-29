import SwiftUI

/// An artist's page, opened with "Go to Artist", laid out like Apple Music's: a large header
/// with Play, the latest release, top songs in swipeable columns, and carousels of albums,
/// singles and EPs, and releases they appear on. Everything comes from Apple's catalog; on
/// YouTube, each song's video is found when it's about to play.
struct ArtistView: View {
    /// The song the artist was opened from.
    let track: Track

    @Environment(CatalogBrowser.self) private var catalog
    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router
    @State private var artist: LoadState<Artist?> = .idle
    @State private var pageSize: CGSize = .zero
    /// The name moves into the navigation bar once the header scrolls away, like Apple Music.
    @State private var isPastHeader = false
    @State private var isShowingAllSongs = false

    private var loadedArtist: Artist? { artist.value ?? nil }

    /// As tall as the page is wide, but never more than half of it, so wide windows keep content in view.
    private var headerHeight: CGFloat {
        min(pageSize.width, pageSize.height * Layout.artistHeaderMaxHeightFraction)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { Palette.backgroundGradient.ignoresSafeArea() }
            .navigationTitle(isPastHeader ? loadedArtist?.name ?? "" : "")
            .navigationTitleStyle(.inline)
            .task {
                if artist.value == nil { await load() }
            }
    }

    @ViewBuilder private var content: some View {
        switch artist {
        case .idle, .loading:
            LoadingStateView("Finding the artist…")
        case .failed(let error):
            ErrorStateView(error: error) {
                Task { await load() }
            }
        case .loaded(nil):
            EmptyStateView(
                title: "No Artist Found",
                systemImage: "music.mic",
                message: "Apple's music catalog doesn't list this artist."
            )
        case .loaded(let artist?):
            page(for: artist)
        }
    }

    private func page(for artist: Artist) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxLarge) {
                header(for: artist)
                if let latest = artist.latestRelease {
                    latestRelease(latest)
                }
                if !artist.tracks.isEmpty {
                    topSongs(by: artist)
                }
                releaseShelf("Albums", releases: artist.albums)
                releaseShelf("Singles & EPs", releases: artist.singles)
                releaseShelf("Appears On", releases: artist.appearsOn)
            }
            .padding(.bottom, Spacing.xxxLarge)
        }
        // The header runs up under the navigation bar and the status bar.
        .ignoresSafeArea(.container, edges: .top)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            pageSize = size
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y > headerHeight / 2
        } action: { _, isPast in
            isPastHeader = isPast
        }
        .navigationDestination(isPresented: $isShowingAllSongs) {
            ArtistSongsView(artist: artist, openedFrom: track)
        }
    }

    // MARK: Sections

    /// Apple's catalog has no artist photos, so the cover of their most popular song stands in.
    private func header(for artist: Artist) -> some View {
        let cover = artist.tracks.first
        return ZStack(alignment: .bottom) {
            ArtworkView(
                url: cover.flatMap { $0.largeArtworkURL ?? $0.artworkURL },
                cornerRadius: Radius.none,
                placeholderSymbol: "music.mic"
            )
            // Keeps the name readable on light artwork.
            LinearGradient(colors: [.clear, Palette.scrim], startPoint: .center, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: Spacing.medium) {
                Text(artist.name)
                    .font(Typography.artistName)
                    .foregroundStyle(Palette.onPlayer)
                    .lineLimit(Layout.cardTitleLineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Button { play(artist, from: 0) } label: {
                    Image(systemName: "play.fill")
                        .font(Typography.headerPlay)
                        .foregroundStyle(Palette.onBrand)
                        .frame(width: TouchTarget.secondary, height: TouchTarget.secondary)
                        .background(Circle().fill(Palette.brand))
                }
                .buttonStyle(.plain)
                .disabled(artist.tracks.isEmpty)
                .accessibilityLabel("Play \(artist.name)")
            }
            .padding(Spacing.large)
        }
        .frame(height: headerHeight)
        .clipped()
    }

    private func latestRelease(_ release: AlbumSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            SectionHeader(title: "Latest Release")
            Button { router.showAlbum(id: release.id, openedFrom: track) } label: {
                HStack(spacing: Spacing.medium) {
                    ArtworkView(
                        url: release.largeArtworkURL ?? release.artworkURL,
                        size: ArtworkSize.latestRelease,
                        cornerRadius: Radius.medium
                    )
                    VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                        if let date = release.releaseDate {
                            Text(date, format: .dateTime.day().month(.abbreviated).year())
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        Text(release.title)
                            .font(Typography.headline)
                            .lineLimit(Layout.cardTitleLineLimit)
                        if let count = release.trackCount {
                            Text("^[\(count) song](inflect: true)")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    Spacer(minLength: Spacing.small)
                    Image(systemName: "chevron.forward")
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityHidden(true)
                }
                .padding(Spacing.medium)
                .background(Palette.cardFill, in: .rect(cornerRadius: Radius.large))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .pointerHover(.highlight)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, Spacing.large)
    }

    /// Four songs to a column, swiped through sideways, like Apple Music's Top Songs.
    private func topSongs(by artist: Artist) -> some View {
        let tracks = playableTracks(by: artist)
        let shown = Array(tracks.prefix(Layout.songColumnsShown))
        return VStack(alignment: .leading, spacing: Spacing.medium) {
            SectionHeader(
                title: "Top Songs",
                actionTitle: tracks.count > shown.count ? "See All" : nil,
                action: { isShowingAllSongs = true }
            )
            .padding(.horizontal, Spacing.large)
            SongColumns(tracks: shown, pageWidth: pageSize.width) { index, song in
                SongRow(for: song, showsArtist: false) {
                    player.play(tracks, startingAt: index)
                } label: {
                    TrackRow(
                        track: song,
                        isCurrent: CatalogPlayback.isCurrent(song, in: player),
                        subtitle: song.albumAndYear
                    ) {
                        EmptyView()
                    }
                }
            }
        }
    }

    @ViewBuilder private func releaseShelf(_ title: LocalizedStringKey, releases: [AlbumSummary]) -> some View {
        if !releases.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                SectionHeader(title: title)
                    .padding(.horizontal, Spacing.large)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: Spacing.large) {
                        ForEach(releases) { release in
                            Button { router.showAlbum(id: release.id, openedFrom: track) } label: {
                                ReleaseCard(release: release)
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

    // MARK: Playback

    private func playableTracks(by artist: Artist) -> [Track] {
        CatalogPlayback.tracks(artist.tracks, openedFrom: track)
    }

    private func play(_ artist: Artist, from index: Int) {
        player.play(playableTracks(by: artist), startingAt: index)
    }

    private func load() async {
        await refreshContent($artist) { try await catalog.artist(of: track) }
    }
}

/// Every one of the artist's songs, from Top Songs' See All.
private struct ArtistSongsView: View {
    let artist: Artist
    /// The song the artist was opened from, which decides how the songs play.
    let openedFrom: Track

    @Environment(PlayerController.self) private var player

    var body: some View {
        let tracks = CatalogPlayback.tracks(artist.tracks, openedFrom: openedFrom)
        TrackCollection(tracks, id: { _, song in song.id }) { index, song in
            SongRow(for: song, showsArtist: false) {
                player.play(tracks, startingAt: index)
            } label: {
                TrackRow(
                    track: song,
                    isCurrent: CatalogPlayback.isCurrent(song, in: player),
                    subtitle: song.albumAndYear
                )
            }
        }
        .background { Palette.backgroundGradient.ignoresSafeArea() }
        .navigationTitle("Top Songs")
        .navigationTitleStyle(.inline)
    }
}

/// An album, single or EP in an artist's carousels: artwork, title and year.
private struct ReleaseCard: View {
    let release: AlbumSummary
    @Environment(\.isWideLayout) private var isWideLayout

    private var side: CGFloat { isWideLayout ? ArtworkSize.cardLarge : ArtworkSize.card }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            ArtworkView(url: release.largeArtworkURL ?? release.artworkURL, size: side, cornerRadius: Radius.medium)
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(release.title)
                    .font(Typography.cardTitle)
                    .lineLimit(Layout.cardTitleLineLimit, reservesSpace: true)
                if let year = release.releaseYear {
                    Text(verbatim: String(year))
                        .font(Typography.rowSubtitle)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .frame(width: side, alignment: .leading)
        .contentShape(.rect)
        .pointerHover(.lift)
        .accessibilityElement(children: .combine)
    }
}

private extension Track {
    /// "Album · 2013", like the lines under Apple Music's top songs.
    var albumAndYear: String? {
        let parts = [albumTitle, releaseYear.map(String.init)].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
