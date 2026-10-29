import SwiftUI

/// Every recently added song from Home's shelf, newest first.
struct RecentlyAddedView: View {
    let entries: [AddedTrack]

    @Environment(PlayerController.self) private var player

    private var tracks: [Track] { entries.map(\.track) }

    var body: some View {
        Group {
            if entries.isEmpty {
                EmptyStateView(
                    title: "Nothing Added Yet",
                    systemImage: "text.badge.plus",
                    message: "Songs you add to your playlists show up here."
                )
            } else {
                TrackCollection(entries, id: { _, entry in entry.id }) { index, entry in
                    SongRow(for: entry.track) {
                        player.play(tracks, startingAt: index)
                    } label: {
                        TrackRow(track: entry.track, isCurrent: player.currentTrack?.id == entry.track.id) {
                            Text(entry.addedAt, format: .relative(presentation: .named))
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Palette.backgroundGradient.ignoresSafeArea() }
        .navigationTitle("Recently Added")
        .navigationTitleStyle(.large)
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Play All", systemImage: "play.fill") { player.play(tracks) }
                }
            }
        }
    }
}
