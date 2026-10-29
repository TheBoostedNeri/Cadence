import SwiftData
import SwiftUI

struct RecentsView: View {
    @Environment(ServiceHub.self) private var hub
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack(path: router.path(for: .recents)) {
            RecentPlaysList(service: hub.current)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { Palette.backgroundGradient.ignoresSafeArea() }
                .navigationTitle("Recently Played")
                .catalogPageDestinations()
        }
    }
}

/// The songs played on one service, newest first. Each service keeps its own history, so
/// switching services never mixes another's songs in.
private struct RecentPlaysList: View {
    let service: MusicService

    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Query private var recentPlays: [RecentPlay]
    @State private var isConfirmingClear = false
    @State private var historyError: AppError?

    init(service: MusicService) {
        self.service = service
        let source = service.rawValue
        _recentPlays = Query(
            filter: #Predicate<RecentPlay> { $0.source == source },
            sort: \.lastPlayedAt,
            order: .reverse
        )
    }

    var body: some View {
        content
            .toolbar {
                if !recentPlays.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear", role: .destructive) { isConfirmingClear = true }
                    }
                }
            }
            .confirmationDialog(
                "Clear \(service.name) history?",
                isPresented: $isConfirmingClear,
                titleVisibility: .visible
            ) {
                Button("Clear History", role: .destructive, action: clearHistory)
            } message: {
                Text("This removes songs you played on \(service.name) from this device. Your playlists aren't affected.")
            }
            .errorAlert($historyError)
    }

    @ViewBuilder private var content: some View {
        if recentPlays.isEmpty {
            EmptyStateView(
                title: "Nothing Played Yet",
                systemImage: "clock.arrow.circlepath",
                message: "Songs you play on \(service.name) show up here so you can jump back in."
            ) {
                Button("Browse Home", systemImage: "house") { router.selectedTab = .home }
                    .buttonStyle(.glassProminent)
            }
        } else {
            TrackCollection(recentPlays, id: { _, play in play.id }, onRemove: remove) { index, play in
                SongRow(
                    for: play.track,
                    removal: TrackRemoval(title: "Remove from Recently Played") { remove(play) }
                ) {
                    player.play(recentPlays.map(\.track), startingAt: index)
                } label: {
                    TrackRow(track: play.track, isCurrent: player.currentTrack?.id == play.videoID) {
                        Text(play.lastPlayedAt, format: .relative(presentation: .named))
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }
    }

    private func remove(_ play: RecentPlay) {
        modelContext.delete(play)
        save()
    }

    private func clearHistory() {
        let source = service.rawValue
        do {
            try modelContext.delete(model: RecentPlay.self, where: #Predicate { $0.source == source })
            save()
        } catch {
            historyError = AppError(error)
        }
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            historyError = AppError(error)
        }
    }
}

#Preview {
    RecentsView()
        .appEnvironment(.preview())
}
