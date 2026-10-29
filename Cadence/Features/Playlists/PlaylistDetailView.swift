import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist

    @Environment(LibraryStore.self) private var library
    @Environment(ServiceHub.self) private var hub
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var entries: LoadState<[PlaylistEntry]> = .idle
    @State private var actionError: AppError?
    @State private var renaming: Playlist?
    @State private var deleting: Playlist?

    /// Picks up a new name as soon as it's saved.
    private var current: Playlist { library.current(playlist) }

    private var canEdit: Bool {
        hub.catalog.isConnected && hub.catalog.capabilities.contains(.editPlaylists)
    }

    private var tracks: [Track] { entries.value?.map(\.track) ?? [] }

    var body: some View {
        SongListPage {
            header
        } rows: {
            entriesContent
        }
        .background { Palette.backgroundGradient.ignoresSafeArea() }
        .navigationTitle(current.title)
        .navigationTitleStyle(.inline)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Menu("More", systemImage: "ellipsis") {
                        PlaylistEditMenuItems(playlist: current, renaming: $renaming, deleting: $deleting)
                    }
                }
            }
        }
        // A deleted playlist's page closes. In the Mac sidebar its entry disappears, and the
        // window moves on to All Playlists.
        .playlistEditor(renaming: $renaming, deleting: $deleting) { dismiss() }
        .task {
            if entries.value == nil { await load() }
        }
        .refreshable { await load() }
        .errorAlert($actionError)
    }

    private var header: some View {
        VStack(spacing: Spacing.large) {
            ArtworkView(
                url: current.largeArtworkURL ?? current.artworkURL,
                size: ArtworkSize.header,
                cornerRadius: Radius.large,
                placeholderSymbol: "music.note.list"
            )
            .shadow(color: Palette.shadow, radius: Elevation.shadowRadius, y: Elevation.shadowOffsetY)

            VStack(spacing: Spacing.xSmall) {
                Text(current.title)
                    .font(Typography.title)
                    .multilineTextAlignment(.center)
                if let privacy = current.privacy {
                    Label(privacy.title, systemImage: privacy.systemImage)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }

            PlayShuffleButtons { play(shuffled: $0) }
                .disabled(tracks.isEmpty)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.large)
    }

    @ViewBuilder private var entriesContent: some View {
        switch entries {
        case .idle, .loading:
            LoadingStateView("Loading songs…")
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        case .failed(let error):
            ErrorStateView(error: error) {
                Task { await load() }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        case .loaded(let items) where items.isEmpty:
            EmptyStateView(
                title: "This Playlist Is Empty",
                systemImage: "music.note",
                message: "Long-press any song in Home, Search or Recents to add it here."
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        case .loaded(let items):
            ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                SongRow(for: entry.track, removal: removal(for: entry)) {
                    player.play(items.map(\.track), startingAt: index)
                } label: {
                    TrackRow(track: entry.track, isCurrent: player.currentTrack?.id == entry.track.id)
                }
                .swipeActions {
                    if hub.catalog.capabilities.contains(.removeFromPlaylists) {
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            Task { await remove(entry) }
                        }
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
    }

    private func load() async {
        if let error = await refreshContent($entries, operation: { try await library.entries(in: playlist) }) {
            actionError = error
        }
    }

    private func play(shuffled: Bool) {
        player.play(shuffled ? tracks.shuffled() : tracks)
    }

    /// Lets pointer and keyboard users remove songs too, since they can't swipe.
    private func removal(for entry: PlaylistEntry) -> TrackRemoval? {
        guard hub.catalog.capabilities.contains(.removeFromPlaylists) else { return nil }
        return TrackRemoval(title: "Remove from Playlist") { Task { await remove(entry) } }
    }

    /// Removes optimistically and restores the row if YouTube rejects the change.
    private func remove(_ entry: PlaylistEntry) async {
        guard case .loaded(var items) = entries, let index = items.firstIndex(of: entry) else { return }
        items.remove(at: index)
        entries = .loaded(items)
        do {
            try await library.remove(entry, from: playlist)
        } catch {
            if case .loaded(var current) = entries {
                current.insert(entry, at: min(index, current.count))
                entries = .loaded(current)
            }
            actionError = AppError(error)
        }
    }
}
