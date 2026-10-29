// iPhone and iPad only: the Mac's player is in the window toolbar (see `MacPlayerToolbar`).
#if os(iOS)
import SwiftUI

/// The mini player in the tab bar's bottom accessory, like Apple Music's. With nothing to play it
/// says so and greys out its buttons instead of hiding them. Tapping it (or Play) opens Now
/// Playing, because the YouTube player has to be visible while it plays.
struct MiniPlayerView: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    private var isExpanded: Bool { placement == .expanded }

    var body: some View {
        let track = player.currentTrack
        HStack(spacing: Spacing.medium) {
            // With nothing playing, the empty cover shows a music note, as in Apple Music.
            ArtworkView(url: track?.artworkURL, size: ArtworkSize.mini)
            VStack(alignment: .leading, spacing: Spacing.none) {
                Text(track?.title ?? String(localized: "Not Playing"))
                    .font(Typography.miniPlayerTitle)
                    .foregroundStyle(track == nil ? Palette.textSecondary : Palette.textPrimary)
                    .lineLimit(1)
                if isExpanded, let track {
                    Text(subtitle(for: track))
                        .font(Typography.miniPlayerSubtitle)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Spacing.small)
            controls(hasTrack: track != nil)
        }
        .padding(.horizontal, Spacing.medium)
        .contentShape(.rect)
        .onTapGesture { player.presentNowPlaying() }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open Now Playing") { player.presentNowPlaying() }
    }

    private func controls(hasTrack: Bool) -> some View {
        HStack(spacing: Spacing.none) {
            MiniPlayerButton(
                player.isPlaying ? "Pause" : "Play",
                systemImage: player.isPlaying ? "pause.fill" : "play.fill",
                isEnabled: hasTrack
            ) {
                player.togglePlayPause()
            }
            if isExpanded {
                MiniPlayerButton("Next", systemImage: "forward.fill", isEnabled: player.hasNext) {
                    player.next()
                }
            }
        }
    }

    private func subtitle(for track: Track) -> String {
        if case .failed(let error) = player.status { return error.title }
        return track.artist
    }
}

/// A transport button that greys out, rather than disappearing, when there's nothing to control.
private struct MiniPlayerButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String, isEnabled: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(Typography.miniPlayerControl)
                .foregroundStyle(isEnabled ? Palette.textPrimary : Palette.textDisabled)
                .contentTransition(.symbolEffect(.replace))
                .frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .pointerHover(.highlight)
    }
}
#endif
