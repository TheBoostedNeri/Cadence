import SwiftUI

struct CreatePlaylistSheet: View {
    var onCreated: (Playlist) -> Void = { _ in }

    @Environment(LibraryStore.self) private var library
    @Environment(ServiceHub.self) private var hub
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var privacy: PlaylistPrivacy = .private
    @State private var isSaving = false
    @State private var error: AppError?
    @FocusState private var isTitleFocused: Bool

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isTitleTooLong: Bool { trimmedTitle.count > YouTubeAPILimits.maxPlaylistTitleLength }
    private var canSave: Bool { !trimmedTitle.isEmpty && !isTitleTooLong && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Playlist name", text: $title)
                        .focused($isTitleFocused)
                        .submitLabel(.done)
                        .onSubmit(save)
                } footer: {
                    if isTitleTooLong {
                        Text("Names can be up to \(YouTubeAPILimits.maxPlaylistTitleLength) characters.")
                            .foregroundStyle(Palette.destructive)
                    }
                }

                if hub.catalog.capabilities.contains(.playlistPrivacy) {
                    Section {
                        Picker("Visibility", selection: $privacy) {
                            ForEach(PlaylistPrivacy.allCases) { option in
                                Label(option.title, systemImage: option.systemImage).tag(option)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } header: {
                        Text("Visibility")
                    } footer: {
                        Text(privacy.explanation)
                    }
                }
            }
            .navigationTitle("New Playlist")
            .navigationTitleStyle(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Create", action: save)
                            .disabled(!canSave)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .errorAlert($error)
            .onAppear { isTitleFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let playlist = try await library.createPlaylist(title: trimmedTitle, privacy: privacy)
                onCreated(playlist)
                dismiss()
            } catch {
                self.error = AppError(error)
            }
        }
    }
}

struct AddToPlaylistSheet: View {
    let tracks: [Track]

    @Environment(ServiceHub.self) private var hub
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var savingPlaylistID: Playlist.ID?
    /// How many songs are in so far, while several are being added.
    @State private var addedCount = 0
    @State private var addedPlaylistID: Playlist.ID?
    /// Songs YouTube had no video for, which were left out.
    @State private var missingCount = 0
    @State private var isShowingMissing = false
    @State private var isCreatingPlaylist = false
    @State private var error: AppError?

    private var otherService: MusicService? {
        tracks.first { $0.source != hub.current }?.source
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Add to Playlist")
                .navigationTitleStyle(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                            .disabled(savingPlaylistID != nil)
                    }
                    if hub.catalog.isConnected && hub.catalog.capabilities.contains(.createPlaylists) {
                        ToolbarItem(placement: .primaryAction) {
                            Button("New Playlist", systemImage: "plus") { isCreatingPlaylist = true }
                                .disabled(savingPlaylistID != nil)
                        }
                    }
                }
                .task(id: hub.connectionKey) {
                    if hub.catalog.isConnected && library.playlists.value == nil {
                        await library.loadPlaylists()
                    }
                }
                .sheet(isPresented: $isCreatingPlaylist) {
                    CreatePlaylistSheet { playlist in
                        Task { await add(to: playlist) }
                    }
                }
                .errorAlert($error)
                .alert("Some Songs Weren't Added", isPresented: $isShowingMissing) {
                    Button("OK") { dismiss() }
                } message: {
                    Text("YouTube has no video for ^[\(missingCount) song](inflect: true), so it was left out. The rest were added.")
                }
                .sensoryFeedback(.success, trigger: addedPlaylistID)
                .interactiveDismissDisabled(savingPlaylistID != nil)
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private var content: some View {
        if let otherService {
            EmptyStateView(
                title: "Different Service",
                systemImage: "arrow.left.arrow.right",
                message: LocalizedStringKey(String(localized: "These songs are from \(otherService.name). Switch to it in Settings to add them to a playlist there."))
            )
        } else if !hub.catalog.isConfigured {
            ErrorStateView(error: .missingConfiguration(.googleClientID))
        } else if !hub.catalog.isConnected {
            EmptyStateView(
                title: "Connect to Save Songs",
                systemImage: "text.badge.plus",
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
            case .loaded(let playlists):
                List {
                    Section {
                        songsSummary
                    }
                    Section("Your Playlists") {
                        if playlists.isEmpty {
                            Button("Create Your First Playlist", systemImage: "plus") { isCreatingPlaylist = true }
                        }
                        ForEach(playlists) { playlist in
                            playlistButton(playlist)
                        }
                    }
                }
            }
        }
    }

    /// The song, or how many songs and the first few titles.
    @ViewBuilder private var songsSummary: some View {
        if let track = tracks.first, tracks.count == 1 {
            TrackRow(track: track)
        } else {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text("^[\(tracks.count) song](inflect: true)")
                    .font(Typography.rowTitle)
                Text(tracks.prefix(PlaylistAdditionSummary.titlesShown).map(\.title).formatted(.list(type: .and)))
                    .font(Typography.rowSubtitle)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(Layout.cardTitleLineLimit)
            }
        }
    }

    private func playlistButton(_ playlist: Playlist) -> some View {
        Button {
            Task { await add(to: playlist) }
        } label: {
            HStack {
                PlaylistRow(playlist: playlist)
                Spacer()
                if savingPlaylistID == playlist.id {
                    if tracks.count > 1 {
                        Text("\(addedCount) of \(tracks.count)")
                            .font(Typography.monospacedCaption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    ProgressView()
                } else if addedPlaylistID == playlist.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.success)
                        .accessibilityLabel("Added")
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(savingPlaylistID != nil)
    }

    /// Adds the songs in order. One YouTube has no video for is skipped and counted; any other
    /// failure stops, leaving the songs before it added.
    private func add(to playlist: Playlist) async {
        savingPlaylistID = playlist.id
        addedCount = 0
        missingCount = 0
        defer { savingPlaylistID = nil }
        for track in tracks {
            do {
                try await library.add(track, to: playlist)
            } catch AppError.playback(.noYouTubeMatch) {
                missingCount += 1
            } catch {
                self.error = AppError(error)
                return
            }
            addedCount += 1
        }
        addedPlaylistID = playlist.id
        if missingCount > 0 {
            isShowingMissing = true
        } else {
            try? await Task.sleep(for: Motion.confirmationHold)
            dismiss()
        }
    }
}

private enum PlaylistAdditionSummary {
    static let titlesShown = 3
}

/// Rename and Delete for one of the user's playlists, in its page's ⋯ menu and its long-press menu.
struct PlaylistEditMenuItems: View {
    let playlist: Playlist
    @Binding var renaming: Playlist?
    @Binding var deleting: Playlist?

    var body: some View {
        Button("Rename…", systemImage: "pencil") { renaming = playlist }
        Button("Delete Playlist…", systemImage: "trash", role: .destructive) { deleting = playlist }
    }
}

/// The rename prompt and the delete confirmation for a playlist, and the work behind them.
private struct PlaylistEditor: ViewModifier {
    @Binding var renaming: Playlist?
    @Binding var deleting: Playlist?
    let onDeleted: () -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(ServiceHub.self) private var hub
    @State private var title = ""
    @State private var error: AppError?

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func canRename(_ playlist: Playlist) -> Bool {
        !trimmedTitle.isEmpty
            && trimmedTitle.count <= YouTubeAPILimits.maxPlaylistTitleLength
            && trimmedTitle != playlist.title
    }

    func body(content: Content) -> some View {
        content
            .alert("Rename Playlist", isPresented: isPresented($renaming), presenting: renaming) { playlist in
                TextField("Playlist name", text: $title)
                Button("Cancel", role: .cancel) {}
                Button("Rename") { rename(playlist) }
                    .disabled(!canRename(playlist))
            } message: { _ in
                Text("Names can be up to \(YouTubeAPILimits.maxPlaylistTitleLength) characters.")
            }
            .onChange(of: renaming) { _, playlist in
                if let playlist { title = playlist.title }
            }
            .confirmationDialog(
                "Delete \u{201C}\(deleting?.title ?? "")\u{201D}?",
                isPresented: isPresented($deleting),
                titleVisibility: .visible,
                presenting: deleting
            ) { playlist in
                Button("Delete Playlist", role: .destructive) { delete(playlist) }
            } message: { _ in
                Text("This deletes the playlist from your \(hub.current.name) account and can't be undone. The songs themselves aren't affected.")
            }
            .errorAlert($error)
    }

    private func isPresented(_ item: Binding<Playlist?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }

    private func rename(_ playlist: Playlist) {
        let newTitle = trimmedTitle
        Task {
            do {
                try await library.rename(playlist, to: newTitle)
            } catch {
                self.error = AppError(error)
            }
        }
    }

    private func delete(_ playlist: Playlist) {
        Task {
            do {
                try await library.delete(playlist)
                onDeleted()
            } catch {
                self.error = AppError(error)
            }
        }
    }
}

extension View {
    /// Shows the rename prompt or delete confirmation when `renaming` or `deleting` is set.
    func playlistEditor(
        renaming: Binding<Playlist?>,
        deleting: Binding<Playlist?>,
        onDeleted: @escaping () -> Void = {}
    ) -> some View {
        modifier(PlaylistEditor(renaming: renaming, deleting: deleting, onDeleted: onDeleted))
    }
}

private struct AddToPlaylistPresenter: ViewModifier {
    /// Only one presenter may be active, so the sheet attaches to whichever view is frontmost.
    let isActive: Bool
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content.sheet(item: Binding(
            get: { isActive ? router.pendingPlaylistAddition : nil },
            set: { router.pendingPlaylistAddition = $0 }
        )) { addition in
            AddToPlaylistSheet(tracks: addition.tracks)
        }
    }
}

extension View {
    func addToPlaylistSheet(isActive: Bool) -> some View {
        modifier(AddToPlaylistPresenter(isActive: isActive))
    }
}
