import SwiftUI

struct TrackRow<Accessory: View>: View {
    let track: Track
    var isCurrent = false
    /// Shown under the title in place of the artist.
    var subtitle: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: Spacing.medium) {
            ArtworkView(url: track.artworkURL, size: ArtworkSize.row)
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(track.title)
                    .font(Typography.rowTitle)
                    .foregroundStyle(isCurrent ? Palette.brand : Palette.textPrimary)
                    .lineLimit(1)
                Text(subtitle ?? track.artist)
                    .font(Typography.rowSubtitle)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.small)
            accessory
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

extension TrackRow where Accessory == TrackDurationLabel {
    init(track: Track, isCurrent: Bool = false, subtitle: String? = nil) {
        self.init(track: track, isCurrent: isCurrent, subtitle: subtitle) {
            TrackDurationLabel(duration: track.duration)
        }
    }
}

struct TrackDurationLabel: View {
    let duration: TimeInterval?

    var body: some View {
        if let duration {
            Text(TimeFormatting.string(from: duration))
                .font(Typography.monospacedCaption)
                .foregroundStyle(Palette.textSecondary)
        }
    }
}

struct TrackCard: View {
    let track: Track
    @Environment(\.isWideLayout) private var isWideLayout

    private var side: CGFloat { isWideLayout ? ArtworkSize.cardLarge : ArtworkSize.card }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            ArtworkView(url: track.artworkURL, size: side, cornerRadius: Radius.medium)
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(track.title)
                    .font(Typography.cardTitle)
                    .lineLimit(Layout.cardTitleLineLimit, reservesSpace: true)
                Text(track.artist)
                    .font(Typography.rowSubtitle)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: side, alignment: .leading)
        .contentShape(.rect)
        .pointerHover(.lift)
        .accessibilityElement(children: .combine)
    }
}

/// Songs as a list on iPhone and in narrow windows, and as a multi-column grid where a wide
/// window has room, like iPad. Removable rows get a swipe action in the list; in the grid, each
/// row's context menu offers removal instead, since grids have no swipe actions.
struct TrackCollection<Item, ID: Hashable, Header: View, Row: View>: View {
    private let items: [Item]
    private let identify: (Int, Item) -> ID
    private let onRemove: ((Item) -> Void)?
    private let header: Header
    private let row: (Int, Item) -> Row
    @Environment(\.isWideLayout) private var isWideLayout

    /// `id` gives each row its identity from its position and item.
    init(
        _ items: [Item],
        id: @escaping (Int, Item) -> ID,
        onRemove: ((Item) -> Void)? = nil,
        @ViewBuilder header: () -> Header,
        @ViewBuilder row: @escaping (Int, Item) -> Row
    ) {
        self.items = items
        self.identify = id
        self.onRemove = onRemove
        self.header = header()
        self.row = row
    }

    private struct Entry: Identifiable {
        let id: ID
        let index: Int
        let item: Item
    }

    private var entries: [Entry] {
        items.enumerated().map { Entry(id: identify($0.offset, $0.element), index: $0.offset, item: $0.element) }
    }

    var body: some View {
        if isWideLayout {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    header
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.textSecondary)
                    LazyVGrid(columns: GridColumns.tracks, spacing: Spacing.medium) {
                        ForEach(entries) { entry in
                            row(entry.index, entry.item)
                                .pointerHover(.highlight)
                        }
                    }
                }
                .padding(Spacing.large)
            }
        } else {
            List {
                Section {
                    listRows
                } header: {
                    header
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var listRows: some View {
        ForEach(entries) { entry in
            row(entry.index, entry.item)
                .swipeActions {
                    if let onRemove {
                        Button("Remove", systemImage: "trash", role: .destructive) { onRemove(entry.item) }
                    }
                }
                .listRowBackground(Color.clear)
        }
    }
}

extension TrackCollection where Header == EmptyView {
    init(
        _ items: [Item],
        id: @escaping (Int, Item) -> ID,
        onRemove: ((Item) -> Void)? = nil,
        @ViewBuilder row: @escaping (Int, Item) -> Row
    ) {
        self.init(items, id: id, onRemove: onRemove, header: { EmptyView() }, row: row)
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    var subtitle: String?
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.medium) {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(title)
                    .font(Typography.sectionTitle)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(Typography.sectionAction)
                    .buttonStyle(.borderless)
            }
        }
    }
}

/// A horizontally scrolling row of track cards; tapping one plays the row from there.
struct TrackCarousel: View {
    let tracks: [Track]
    @Environment(PlayerController.self) private var player

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: Spacing.large) {
                ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                    Button {
                        player.play(tracks, startingAt: index)
                    } label: {
                        TrackCard(track: track)
                    }
                    .buttonStyle(.plain)
                    .trackContextMenu(for: track)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, Spacing.large, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }
}

/// A way to take a song out of the list it's shown in, offered at the end of its context menu.
struct TrackRemoval {
    let title: LocalizedStringKey
    let action: () -> Void
}

/// The actions for a song, shared by its long-press menu and its ⋯ button.
struct TrackMenuItems: View {
    let track: Track
    var removal: TrackRemoval?
    var showsAlbum = true
    var showsArtist = true
    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
            player.playNext(track)
        }
        Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
            player.playLast(track)
        }
        Button("Add to Playlist…", systemImage: "text.badge.plus") {
            router.addToPlaylist([track])
        }
        if showsAlbum {
            Button("Go to Album", systemImage: "square.stack") {
                router.showAlbum(for: track)
            }
        }
        if showsArtist {
            Button("Go to Artist", systemImage: "music.mic") {
                router.showArtist(for: track)
            }
        }
        ShareLink(item: track.externalURL) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Link(destination: track.externalURL) {
            Label("Open in \(track.source.appName)", systemImage: "arrow.up.right.square")
        }
        if let removal {
            Divider()
            Button(removal.title, systemImage: "trash", role: .destructive, action: removal.action)
        }
    }
}

/// Long-press (or secondary-click) actions for a song. Songs can also be dragged into other
/// apps, like Notes or Messages, as a link.
private struct TrackContextMenu: ViewModifier {
    let track: Track
    let removal: TrackRemoval?
    let showsAlbum: Bool
    let showsArtist: Bool

    func body(content: Content) -> some View {
        content
            .draggable(track.externalURL)
            .contextMenu {
                TrackMenuItems(track: track, removal: removal, showsAlbum: showsAlbum, showsArtist: showsArtist)
            }
    }
}

/// The ⋯ at the end of a song row, like Apple Music's, with the same actions as a long press.
struct TrackMenuButton: View {
    let track: Track
    var removal: TrackRemoval?
    var showsAlbum = true
    var showsArtist = true

    var body: some View {
        Menu {
            TrackMenuItems(track: track, removal: removal, showsAlbum: showsAlbum, showsArtist: showsArtist)
        } label: {
            Image(systemName: "ellipsis")
                .font(Typography.rowSubtitle.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        #if os(macOS)
        .menuIndicator(.hidden)
        .fixedSize()
        #endif
        .accessibilityLabel("More")
    }
}

/// A song in a list, like Apple Music's: tapping it plays, and the ⋯ button or a long press
/// offers everything else.
struct SongRow<Label: View>: View {
    private let track: Track
    private let removal: TrackRemoval?
    private let showsAlbum: Bool
    private let showsArtist: Bool
    private let play: () -> Void
    private let label: Label

    /// `showsAlbum` and `showsArtist` are off for songs already shown on that page.
    init(
        for track: Track,
        removal: TrackRemoval? = nil,
        showsAlbum: Bool = true,
        showsArtist: Bool = true,
        play: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.track = track
        self.removal = removal
        self.showsAlbum = showsAlbum
        self.showsArtist = showsArtist
        self.play = play
        self.label = label()
    }

    var body: some View {
        // Separate plain buttons, so a tap on ⋯ doesn't also play the song.
        HStack(spacing: Spacing.xSmall) {
            Button(action: play) { label }
                .buttonStyle(.plain)
            TrackMenuButton(track: track, removal: removal, showsAlbum: showsAlbum, showsArtist: showsArtist)
        }
        .trackContextMenu(for: track, removal: removal, showsAlbum: showsAlbum, showsArtist: showsArtist)
    }
}

extension View {
    /// `showsAlbum` and `showsArtist` are off for songs already shown on that page.
    func trackContextMenu(
        for track: Track,
        removal: TrackRemoval? = nil,
        showsAlbum: Bool = true,
        showsArtist: Bool = true
    ) -> some View {
        modifier(TrackContextMenu(track: track, removal: removal, showsAlbum: showsAlbum, showsArtist: showsArtist))
    }
}
