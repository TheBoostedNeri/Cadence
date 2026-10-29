import SwiftUI

/// The album a song is from, opened with "Go to Album". Albums come from Apple's catalog; on
/// YouTube, each song's video is found when it's about to play.
struct AlbumView: View {
    /// The song the album was opened from, or for an album picked on an artist's page, the song
    /// that artist was opened from. It decides whether the album plays on Apple Music or YouTube.
    let track: Track
    /// Set when the album was picked by ID rather than found from `track`.
    var albumID: String?

    @Environment(CatalogBrowser.self) private var catalog
    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router
    @State private var album: LoadState<Album?> = .idle

    private var loadedAlbum: Album? { album.value ?? nil }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { Palette.backgroundGradient.ignoresSafeArea() }
            .navigationTitle(loadedAlbum?.title ?? "")
            .navigationTitleStyle(.inline)
            .task {
                if album.value == nil { await load() }
            }
    }

    @ViewBuilder private var content: some View {
        switch album {
        case .idle, .loading:
            LoadingStateView("Finding the album…")
        case .failed(let error):
            ErrorStateView(error: error) {
                Task { await load() }
            }
        case .loaded(nil):
            EmptyStateView(
                title: "No Album Found",
                systemImage: "square.stack",
                message: "Apple's music catalog doesn't list an album for this song."
            )
        case .loaded(let album?):
            SongListPage {
                header(for: album)
            } rows: {
                songs(in: album)
            }
        }
    }

    private func header(for album: Album) -> some View {
        VStack(spacing: Spacing.large) {
            ArtworkView(
                url: album.largeArtworkURL ?? album.artworkURL,
                size: ArtworkSize.header,
                cornerRadius: Radius.large,
                placeholderSymbol: "square.stack"
            )
            .shadow(color: Palette.shadow, radius: Elevation.shadowRadius, y: Elevation.shadowOffsetY)

            VStack(spacing: Spacing.xSmall) {
                Text(album.title)
                    .font(Typography.title)
                Button(album.artist) {
                    // A compilation's artist ("Various Artists") isn't in the catalog, so this
                    // goes to the artist of a song that's credited to the album's artist.
                    router.showArtist(for: album.tracks.first { $0.artist == album.artist } ?? track)
                }
                .font(Typography.headline)
                .foregroundStyle(Palette.brand)
                .buttonStyle(.plain)
                .accessibilityHint("Shows the artist's songs")
                HStack(spacing: Spacing.xSmall) {
                    if let year = album.releaseYear {
                        Text(verbatim: String(year))
                        Text(verbatim: "·")
                            .accessibilityHidden(true)
                    }
                    Text("^[\(album.tracks.count) song](inflect: true)")
                }
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityElement(children: .combine)
            }
            .multilineTextAlignment(.center)

            PlayShuffleButtons { play(album, shuffled: $0) }
                .disabled(album.tracks.isEmpty)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.large)
    }

    @ViewBuilder private func songs(in album: Album) -> some View {
        let tracks = playableTracks(in: album)
        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, song in
            SongRow(for: song, showsAlbum: false) {
                player.play(tracks, startingAt: index)
            } label: {
                AlbumSongRow(
                    number: index + 1,
                    track: song,
                    showsArtist: song.artist != album.artist,
                    isCurrent: CatalogPlayback.isCurrent(song, in: player)
                )
            }
            .listRowBackground(Color.clear)
        }
    }

    private func playableTracks(in album: Album) -> [Track] {
        CatalogPlayback.tracks(album.tracks, openedFrom: track)
    }

    private func play(_ album: Album, shuffled: Bool) {
        let tracks = playableTracks(in: album)
        player.play(shuffled ? tracks.shuffled() : tracks)
    }

    private func load() async {
        await refreshContent($album) {
            if let albumID {
                try await catalog.album(id: albumID)
            } else {
                try await catalog.album(containing: track)
            }
        }
    }
}

/// A numbered album song, like Apple Music: the artist shows only when it isn't the album's.
private struct AlbumSongRow: View {
    let number: Int
    let track: Track
    let showsArtist: Bool
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: Spacing.medium) {
            Group {
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(Palette.brand)
                        .accessibilityHidden(true)
                } else {
                    Text(number, format: .number)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .font(Typography.trackNumber)
            .frame(minWidth: Layout.trackNumberWidth)

            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(track.title)
                    .font(Typography.rowTitle)
                    .foregroundStyle(isCurrent ? Palette.brand : Palette.textPrimary)
                    .lineLimit(1)
                if showsArtist {
                    Text(track.artist)
                        .font(Typography.rowSubtitle)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Spacing.small)
            TrackDurationLabel(duration: track.duration)
        }
        .frame(minHeight: TouchTarget.minimum)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
