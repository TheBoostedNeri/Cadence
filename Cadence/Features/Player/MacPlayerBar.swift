// The Mac only: iPhone and iPad keep the mini player in the tab bar and Now Playing in a sheet.
#if os(macOS)
import SwiftUI

/// What the panel on the right shows under the video, like Apple Music's Lyrics and Up Next.
enum SidePanelMode: String {
    case lyrics
    case upNext
}

extension View {
    /// The Mac's player, floating over the bottom of the content like Apple Music's.
    func macPlayerBar() -> some View {
        safeAreaInset(edge: .bottom, spacing: Spacing.none) {
            MacPlayerBar()
                .padding(.horizontal, Spacing.medium)
                .padding(.bottom, Spacing.medium)
        }
    }
}

/// Shuffle, Previous, Play, Next and Repeat on the left, the song in the middle, and Lyrics,
/// Up Next and volume on the right, in one glass capsule. With nothing playing, the playback
/// buttons grey out and the middle shows a music note.
///
/// It fits whatever width the window leaves it rather than pushing the window wider: as it
/// narrows, the song display shrinks, then Shuffle and Repeat step aside.
private struct MacPlayerBar: View {
    @Environment(PlayerController.self) private var player
    @AppStorage(StorageKey.sidePanelMode) private var panelMode = SidePanelMode.upNext
    @State private var width: CGFloat = 0

    private static let allPlaybackButtons = 5
    private static let essentialPlaybackButtons = 3

    /// The width of `count` bar buttons side by side.
    private static func buttonsWidth(_ count: Int) -> CGFloat {
        TouchTarget.minimum * CGFloat(count) + Spacing.xSmall * CGFloat(count - 1)
    }

    /// The bar's padding and the gaps between its three groups.
    private static let chrome = Spacing.large * 4

    private var showsAllPlaybackButtons: Bool {
        width - Self.chrome - Self.buttonsWidth(Self.allPlaybackButtons) * 2 >= Layout.macDisplayMinWidth
    }

    /// Room for the playback buttons; both sides get at least this, so the song stays centered,
    /// as in Apple Music.
    private var minimumSideWidth: CGFloat {
        Self.buttonsWidth(showsAllPlaybackButtons ? Self.allPlaybackButtons : Self.essentialPlaybackButtons)
    }

    /// Whatever the buttons leave, up to the display's full width; at the narrowest, the artwork.
    private var displayWidth: CGFloat {
        let available = width - Self.chrome - minimumSideWidth * 2
        return min(Layout.macDisplayWidth, max(ArtworkSize.playerBar + Spacing.medium, available))
    }

    /// The sides take whatever the display doesn't, so the buttons sit at the ends of the capsule.
    private var sideWidth: CGFloat {
        max(minimumSideWidth, (width - Self.chrome - displayWidth) / 2)
    }

    var body: some View {
        HStack(spacing: Spacing.large) {
            playbackButtons
                .frame(width: sideWidth, alignment: .leading)
            NowPlayingDisplay()
                .frame(width: displayWidth)
            panelButtons
                .frame(width: sideWidth, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.large)
        // Takes exactly the width it's offered, never more: the groups above are sized from the
        // last width measured here, and without a minimum of zero the window would treat that
        // size as the content's minimum, so opening Now Playing would push everything sideways
        // instead of letting the content narrow.
        .frame(minWidth: Spacing.none, maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
        .frame(height: Layout.macPlayerBarHeight)
        // Keeps the buttons inside the capsule for the moment before the bar re-measures.
        .clipShape(.capsule)
        .glassEffect(.regular, in: .capsule)
    }

    private var playbackButtons: some View {
        let canShuffleAndRepeat = player.supportsShuffleAndRepeat
        return HStack(spacing: Spacing.xSmall) {
            if showsAllPlaybackButtons {
                BarButton("Shuffle", systemImage: "shuffle", font: Typography.barSecondaryControl,
                          isOn: player.isShuffled, isEnabled: canShuffleAndRepeat) {
                    player.toggleShuffle()
                }
            }
            BarButton("Previous", systemImage: "backward.fill", isEnabled: player.hasPrevious) {
                player.previous()
            }
            BarButton(
                player.isPlaying ? "Pause" : "Play",
                systemImage: player.isPlaying ? "pause.fill" : "play.fill",
                font: Typography.barPrimaryControl,
                isEnabled: player.currentTrack != nil
            ) {
                player.togglePlayPause()
            }
            BarButton("Next", systemImage: "forward.fill", isEnabled: player.hasNext) {
                player.next()
            }
            if showsAllPlaybackButtons {
                BarButton(repeatTitle, systemImage: player.repeatMode == .one ? "repeat.1" : "repeat",
                          font: Typography.barSecondaryControl,
                          isOn: player.repeatMode != .off, isEnabled: canShuffleAndRepeat) {
                    player.cycleRepeatMode()
                }
            }
        }
    }

    private var repeatTitle: LocalizedStringKey {
        switch player.repeatMode {
        case .off: "Repeat"
        case .all: "Repeat All"
        case .one: "Repeat One"
        }
    }

    private var panelButtons: some View {
        HStack(spacing: Spacing.xSmall) {
            BarButton("Lyrics", systemImage: "quote.bubble", isOn: isPanelShowing(.lyrics)) {
                togglePanel(.lyrics)
            }
            BarButton("Up Next", systemImage: "list.bullet", isOn: isPanelShowing(.upNext)) {
                togglePanel(.upNext)
            }
            VolumeButton()
        }
    }

    private func isPanelShowing(_ mode: SidePanelMode) -> Bool {
        player.isNowPlayingPresented && panelMode == mode
    }

    /// Like Apple Music, each button opens the panel on its own view, and closes it when that view
    /// is already showing.
    private func togglePanel(_ mode: SidePanelMode) {
        if isPanelShowing(mode) {
            player.isNowPlayingPresented = false
        } else {
            panelMode = mode
            player.isNowPlayingPresented = true
        }
    }
}

/// A plain icon button that greys out when there's nothing to act on and takes the accent color
/// while its option is on.
private struct BarButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let font: Font
    let isOn: Bool
    let isEnabled: Bool
    let action: () -> Void

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        font: Font = Typography.barControl,
        isOn: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.font = font
        self.isOn = isOn
        self.isEnabled = isEnabled
        self.action = action
    }

    private var color: Color {
        guard isEnabled else { return Palette.textDisabled }
        return isOn ? Palette.brand : Palette.textPrimary
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(font)
                .foregroundStyle(color)
                .contentTransition(.symbolEffect(.replace))
                .frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(Text(title))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The song playing: artwork, title, "Artist — Album" and a thin progress bar that shows the
/// times while the pointer is over it. Clicking the artwork shows or hides the panel with the
/// video. With nothing playing, a music note stands in.
private struct NowPlayingDisplay: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        Group {
            if let track = player.currentTrack {
                HStack(spacing: Spacing.medium) {
                    Button {
                        player.isNowPlayingPresented.toggle()
                    } label: {
                        ArtworkView(url: track.artworkURL, size: ArtworkSize.playerBar)
                    }
                    .buttonStyle(.plain)
                    .help(player.isNowPlayingPresented ? "Hide Player" : "Show Player")
                    .accessibilityLabel(player.isNowPlayingPresented ? "Hide Player" : "Show Player")

                    VStack(alignment: .leading, spacing: Spacing.none) {
                        Text(track.title)
                            .font(Typography.displayTitle)
                        Text(subtitle(for: track))
                            .font(Typography.displaySubtitle)
                            .foregroundStyle(Palette.textSecondary)
                        DisplayProgressBar(
                            position: player.currentTime,
                            duration: player.duration,
                            onSeek: player.seek(to:)
                        )
                    }
                    .lineLimit(1)
                }
            } else {
                Image(systemName: "music.note")
                    .font(Typography.barPrimaryControl)
                    .foregroundStyle(Palette.textDisabled)
                    .accessibilityLabel("Not Playing")
            }
        }
        // The bar sets the width; the text truncates to fit. The music note sits in the middle.
        .frame(maxWidth: .infinity, alignment: player.currentTrack == nil ? .center : .leading)
        .clipped()
    }

    /// "Artist — Album", or what went wrong.
    private func subtitle(for track: Track) -> String {
        if case .failed(let error) = player.status { return error.title }
        guard let album = track.albumTitle else { return track.artist }
        return "\(track.artist) — \(album)"
    }
}

/// A slim, clickable progress bar. Dragging previews the new position; letting go seeks there.
private struct DisplayProgressBar: View {
    let position: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var dragPosition: TimeInterval?
    @State private var isHovering = false

    private var shownPosition: TimeInterval { dragPosition ?? position }

    private var fraction: Double {
        duration > 0 ? min(1, max(0, shownPosition / duration)) : 0
    }

    var body: some View {
        HStack(spacing: Spacing.xSmall) {
            if isHovering {
                Text(TimeFormatting.string(from: shownPosition))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Palette.inactive)
                    Capsule()
                        .fill(Palette.textSecondary)
                        .frame(width: proxy.size.width * fraction)
                }
                .frame(height: Layout.displayProgressHeight)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0, proxy.size.width > 0 else { return }
                            dragPosition = min(1, max(0, value.location.x / proxy.size.width)) * duration
                        }
                        .onEnded { _ in
                            if let dragPosition { onSeek(dragPosition) }
                            dragPosition = nil
                        }
                )
            }
            .frame(height: Layout.displayProgressHitHeight)
            if isHovering {
                Text("-\(TimeFormatting.string(from: max(0, duration - shownPosition)))")
            }
        }
        .font(Typography.monospacedCaption)
        .foregroundStyle(Palette.textSecondary)
        .onHover { isHovering = $0 }
        .disabled(duration <= 0)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(TimeFormatting.string(from: position))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(min(duration, position + PlaybackPolicy.accessibilitySeekStep))
            case .decrement: onSeek(max(0, position - PlaybackPolicy.accessibilitySeekStep))
            @unknown default: break
            }
        }
    }
}

/// YouTube's own volume, in a popover like Apple Music's. The speaker fills in with the level.
private struct VolumeButton: View {
    @Environment(PlayerController.self) private var player
    @State private var isShowingSlider = false

    var body: some View {
        Button {
            isShowingSlider.toggle()
        } label: {
            Image(systemName: "speaker.wave.3.fill", variableValue: player.volume)
                .font(Typography.barControl)
                .foregroundStyle(Palette.textPrimary)
                .frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Volume")
        .accessibilityLabel("Volume")
        .popover(isPresented: $isShowingSlider, arrowEdge: .top) {
            Slider(
                value: Binding(get: { player.volume }, set: { player.setVolume($0) }),
                in: 0...PlaybackPolicy.fullVolume
            )
            .frame(width: Layout.macVolumeSliderWidth)
            .padding(Spacing.medium)
            .accessibilityLabel("Volume")
        }
    }
}
#endif
