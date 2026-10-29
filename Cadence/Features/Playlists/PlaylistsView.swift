import SwiftUI

struct PlaylistsView: View {
    @Environment(ServiceHub.self) private var hub
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var library
    @Environment(\.isWideLayout) private var isWideLayout
    @State private var isCreatingPlaylist = false
    @State private var renaming: Playlist?
    @State private var deleting: Playlist?

    private var canEdit: Bool { hub.catalog.capabilities.contains(.editPlaylists) }

    var body: some View {
        @Bindable var library = library

        NavigationStack(path: router.path(for: .playlists)) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { Palette.backgroundGradient.ignoresSafeArea() }
                .navigationTitle("Playlists")
                .catalogPageDestinations()
                .toolbar {
                    if hub.catalog.isConnected && hub.catalog.capabilities.contains(.createPlaylists) {
                        ToolbarItem(placement: .primaryAction) {
                            Button("New Playlist", systemImage: "plus") { isCreatingPlaylist = true }
                        }
                    }
                }
                .navigationDestination(for: Playlist.self) { playlist in
                    PlaylistDetailView(playlist: playlist)
                }
                .sheet(isPresented: $isCreatingPlaylist) {
                    CreatePlaylistSheet()
                }
                .playlistEditor(renaming: $renaming, deleting: $deleting)
                .task(id: hub.connectionKey) {
                    if hub.catalog.isConnected {
                        await library.loadPlaylists()
                    } else {
                        library.reset()
                    }
                }
                .errorAlert($library.refreshError)
        }
    }

    @ViewBuilder private func editMenu(for playlist: Playlist) -> some View {
        if canEdit {
            PlaylistEditMenuItems(playlist: playlist, renaming: $renaming, deleting: $deleting)
        }
    }

    @ViewBuilder private var content: some View {
        if !hub.catalog.isConfigured {
            ErrorStateView(error: .missingConfiguration(.googleClientID))
        } else if !hub.catalog.isConnected {
            EmptyStateView(
                title: "Your Playlists",
                systemImage: "music.note.list",
                message: LocalizedStringKey(hub.catalog.connectPrompt)
            ) {
                ConnectAccountButton()
            }
        } else {
            switch library.playlists {
            case .idle, .loading:
                LoadingStateView("Loading your playlists…")
            case .failed(let error):
                ErrorStateView(error: error) {
                    Task { await library.loadPlaylists() }
                }
            case .loaded(let playlists) where playlists.isEmpty:
                EmptyStateView(
                    title: "No Playlists Yet",
                    systemImage: "music.note.list",
                    message: "Create a playlist, then long-press any song to add it."
                ) {
                    if hub.catalog.capabilities.contains(.createPlaylists) {
                        Button("New Playlist", systemImage: "plus") { isCreatingPlaylist = true }
                            .buttonStyle(.glassProminent)
                    }
                }
            case .loaded(let playlists) where isWideLayout:
                // Wide windows show playlists as a grid of artwork instead of a long list.
                ScrollView {
                    LazyVGrid(columns: GridColumns.cards, spacing: Spacing.xLarge) {
                        ForEach(playlists) { playlist in
                            NavigationLink(value: playlist) {
                                PlaylistCard(playlist: playlist)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { editMenu(for: playlist) }
                        }
                    }
                    .padding(Spacing.large)
                }
                .refreshable { await library.loadPlaylists() }
            case .loaded(let playlists):
                List(playlists) { playlist in
                    NavigationLink(value: playlist) {
                        PlaylistRow(playlist: playlist)
                    }
                    .contextMenu { editMenu(for: playlist) }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await library.loadPlaylists() }
            }
        }
    }
}

struct PlaylistRow: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: Spacing.medium) {
            ArtworkView(url: playlist.artworkURL, size: ArtworkSize.row, placeholderSymbol: "music.note.list")
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(playlist.title)
                    .font(Typography.rowTitle)
                    .lineLimit(1)
                HStack(spacing: Spacing.xSmall) {
                    if let privacy = playlist.privacy {
                        Image(systemName: privacy.systemImage)
                            .accessibilityLabel(privacy.title)
                    }
                    Text("^[\(playlist.itemCount) song](inflect: true)")
                }
                .font(Typography.rowSubtitle)
                .foregroundStyle(Palette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct PlaylistCard: View {
    let playlist: Playlist
    @Environment(\.isWideLayout) private var isWideLayout

    private var side: CGFloat { isWideLayout ? ArtworkSize.cardLarge : ArtworkSize.card }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            ArtworkView(
                url: playlist.artworkURL,
                size: side,
                cornerRadius: Radius.medium,
                placeholderSymbol: "music.note.list"
            )
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(playlist.title)
                    .font(Typography.cardTitle)
                    .lineLimit(1)
                Text("^[\(playlist.itemCount) song](inflect: true)")
                    .font(Typography.rowSubtitle)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(width: side, alignment: .leading)
        .contentShape(.rect)
        .pointerHover(.lift)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    PlaylistsView()
        .appEnvironment(.preview())
}
