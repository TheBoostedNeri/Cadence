import SwiftUI

/// Now Playing, laid out like Apple Music on iPhone: the artwork (or YouTube's video) on top, then
/// the song, a scrubber, playback buttons, volume, and Lyrics, AirPlay and Up Next along the
/// bottom. It's always dark and tinted by the artwork, like Apple Music. YouTube's video stays at
/// least 200×200 and is never covered while it plays.
struct NowPlayingView: View {
    /// Full screen on iPhone, like Apple Music; a panel beside the app in wide windows, like iPad.
    enum Presentation {
        case fullScreen
        case panel
        /// The Mac's panel, like Apple Music's: the player bar has the controls, so it holds just
        /// the video and, under it, the lyrics or Up Next.
        case sidePanel
    }

    /// What takes the artwork's place, from the buttons along the bottom.
    private enum Panel {
        case lyrics
        case queue
    }

    var presentation: Presentation = .fullScreen

    @Environment(PlayerController.self) private var player
    @Environment(LyricsService.self) private var lyricsService
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(StorageKey.youtubeBackgroundPlay) private var isYouTubeBackgroundPlayEnabled = false
    @State private var coverContainerWidth: CGFloat = 0
    @State private var openPanel: Panel?
    #if os(macOS)
    @AppStorage(StorageKey.sidePanelMode) private var sidePanelMode = SidePanelMode.upNext
    #endif
    /// Now Playing's size inside the safe area, which sets how tall the full-bleed artwork is.
    @State private var contentSize: CGSize = .zero
    /// True while the artwork glides between full size and the small header. Up Next's header
    /// scrolls, so once the glide lands it shows its own copy of the artwork, which scrolls and
    /// fades with it.
    @State private var isArtworkGliding = false
    /// The song and controls under the artwork, at their natural height.
    @State private var mainControlsHeight: CGFloat = 0
    /// Over playing lyrics the controls step away after a while, like Apple Music's.
    @State private var areLyricsControlsHidden = false
    /// Bumped when the controls come back, which restarts their countdown.
    @State private var controlsReveals = 0
    /// A finger on the controls keeps them up; lifting it restarts the countdown.
    @GestureState private var isTouchingControls = false
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled

    private var isShowingLyrics: Bool { openPanel == .lyrics }

    var body: some View {
        Group {
            if let track = player.currentTrack {
                #if os(macOS)
                if presentation == .sidePanel {
                    sidePanelContent(for: track)
                } else {
                    content(for: track)
                }
                #else
                content(for: track)
                #endif
            } else {
                EmptyStateView(
                    title: "Nothing Playing",
                    systemImage: "music.note",
                    message: "Pick a song from Home, Playlists or Search."
                )
            }
        }
        #if os(iOS)
        // White on the artwork's colors in light mode too, like Apple Music.
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .top) {
            if presentation == .fullScreen { grabber }
        }
        // The full-screen player is its own presentation, so it can turn the status bar white
        // over its dark background. The iPad panel shares the app's window, so it leaves it be.
        .preferredColorScheme(presentation == .fullScreen ? .dark : nil)
        .presentationBackground(Palette.playerBackground)
        .accessibilityAction(.escape) { close() }
        #endif
        .addToPlaylistSheet(isActive: true)
    }

    private func content(for track: Track) -> some View {
        standardContent(for: track)
            .background { backdrop(for: track) }
    }

    private func standardContent(for track: Track) -> some View {
        let isImmersive = usesImmersiveArtwork(for: track)
        return VStack(spacing: Spacing.large) {
            if isImmersive {
                immersiveArtwork(for: track)
            } else {
                if presentation == .panel {
                    hidePanelButton
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.large)
                }
                if showsVideo(for: track) {
                    cover(for: track)
                        .padding(.horizontal, Spacing.large)
                }
            }
            if let openPanel {
                // Like Apple Music, the artwork steps down to a small header and the lyrics or
                // queue take its place; YouTube's video stays at its minimum size above. The
                // controls sit exactly as they do under the artwork, so switching never moves them.
                VStack(spacing: Spacing.xLarge) {
                    VStack(spacing: Spacing.large) {
                        // Up Next scrolls its header away with the songs, so it draws its own.
                        if openPanel != .queue {
                            compactHeader(for: track)
                                .padding(.horizontal, Spacing.xLarge)
                        }
                        panelBody(openPanel, for: track)
                            .padding(.horizontal, Spacing.large)
                    }
                    if !areControlsHidden {
                        playbackControls
                            .padding(.horizontal, Spacing.xLarge)
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 0).updating($isTouchingControls) { _, isTouching, _ in
                                    isTouching = true
                                }
                            )
                            // They sink and fade away, and rise back in, like Apple Music's.
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.bottom, Spacing.large)
                .overlay(alignment: .bottom) {
                    if areControlsHidden {
                        // Tapping near the bottom brings the controls back, like Apple Music.
                        Color.clear
                            .frame(height: Layout.controlsRevealHeight)
                            .contentShape(.rect)
                            .onTapGesture { revealControls() }
                            .ignoresSafeArea(.container, edges: .bottom)
                            .accessibilityHidden(true)
                    }
                }
                .task(id: controlsCountdown) { await runControlsCountdown() }
                .transition(.opacity)
            } else {
                // The controls sit at the bottom, like Apple Music's; short screens scroll them.
                ViewThatFits(in: .vertical) {
                    mainControls(for: track)
                    ScrollView {
                        mainControls(for: track)
                    }
                    .scrollIndicators(.hidden)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .transition(.opacity)
            }
        }
        // The full-bleed artwork reaches the top edge itself; otherwise there's room for the grabber.
        .padding(.top, isImmersive ? Spacing.none : Spacing.xLarge)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            contentSize = size
        }
        .backgroundPreferenceValue(ArtworkSlotKey.self) { slots in
            movingArtwork(for: track, in: slots)
        }
        .animation(Motion.standard, value: openPanel)
    }

    /// One artwork view drawn behind the content, in whichever slot is showing: full size above
    /// the controls, or small beside the song above the lyrics or queue. Being the same view, it
    /// glides between them as they swap, like Apple Music's, instead of fading out and back in.
    private func movingArtwork(for track: Track, in slots: [ArtworkSlot: Anchor<CGRect>]) -> some View {
        GeometryReader { proxy in
            let isImmersive = openPanel == nil
            let isHandedToQueue = openPanel == .queue && !isArtworkGliding
            if let anchor = slots[isImmersive ? .immersive : .compact], !isHandedToQueue {
                let frame = proxy[anchor]
                ArtworkView(
                    url: track.largeArtworkURL ?? track.artworkURL,
                    cornerRadius: isImmersive ? Radius.none : Radius.small
                )
                .edgeFade(bottom: isImmersive ? immersiveArtworkHeight * Layout.immersiveArtworkFadeFraction : 0)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
            }
        }
        .allowsHitTesting(false)
    }

    /// As tall as the screen is wide, but short enough that the controls fit below without
    /// scrolling, so they sit exactly where they do under the lyrics. Only very large text
    /// shrinks it to its minimum and scrolls the controls instead.
    private var immersiveArtworkHeight: CGFloat {
        let preferred = min(contentSize.width, contentSize.height * Layout.immersiveArtworkMaxHeightFraction)
        let room = contentSize.height - mainControlsHeight - Spacing.large
        return max(min(preferred, room), contentSize.height * Layout.immersiveArtworkMinHeightFraction)
    }

    /// Switches between the artwork, lyrics and Up Next, gliding the artwork between its spots.
    private func showPanel(_ panel: Panel?) {
        isArtworkGliding = true
        withAnimation(Motion.standard) {
            openPanel = panel
        } completion: {
            isArtworkGliding = false
        }
    }

    /// Marks where the artwork goes; `movingArtwork` draws it there.
    private func artworkSlot(_ slot: ArtworkSlot) -> some View {
        Color.clear
            .anchorPreference(key: ArtworkSlotKey.self, value: .bounds) { [slot: $0] }
    }

    // MARK: Hiding controls over lyrics

    private var areControlsHidden: Bool { isShowingLyrics && areLyricsControlsHidden }

    /// The controls only step away while lyrics play untouched, and never under VoiceOver,
    /// which would lose them.
    private var controlsCountdown: ControlsCountdown {
        ControlsCountdown(
            isRunning: isShowingLyrics && player.isPlaying && !isTouchingControls && !isVoiceOverEnabled,
            reveals: controlsReveals
        )
    }

    private func runControlsCountdown() async {
        guard controlsCountdown.isRunning else {
            // Paused, touched or with the lyrics closed, the controls come back.
            if areLyricsControlsHidden && !isTouchingControls {
                withAnimation(Motion.standard) { areLyricsControlsHidden = false }
            }
            return
        }
        guard (try? await Task.sleep(for: Motion.controlsAutoHideDelay)) != nil else { return }
        withAnimation(Motion.standard) { areLyricsControlsHidden = true }
    }

    private func revealControls() {
        controlsReveals += 1
        withAnimation(Motion.standard) { areLyricsControlsHidden = false }
    }

    /// Like Apple Music, artwork fills the top of Now Playing edge to edge wherever it stands in
    /// for video: Apple Music, and YouTube with background play on. With the lyrics or queue open
    /// it steps down to a small header.
    private func usesImmersiveArtwork(for track: Track) -> Bool {
        !showsVideo(for: track) && openPanel == nil
    }

    /// Full-width artwork running up under the status bar, melting into the artwork-colored
    /// background. It stops short of pushing the controls off screen.
    private func immersiveArtwork(for track: Track) -> some View {
        ZStack(alignment: .top) {
            artworkSlot(.immersive)
                .ignoresSafeArea(.container, edges: .top)
            artworkStatus(for: track)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if presentation == .panel {
                hidePanelButton
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.large)
                    .padding(.top, Spacing.large)
            }
        }
        .frame(height: immersiveArtworkHeight)
        .animation(Motion.standard, value: player.status)
    }

    /// Loading and failure shown on top of the artwork.
    @ViewBuilder private func artworkStatus(for track: Track) -> some View {
        switch player.status {
        case .failed(let error):
            ZStack {
                Palette.scrim
                playbackError(error, for: track)
            }
        case .loading:
            ProgressView()
                .controlSize(.large)
                .tint(Palette.onPlayer)
                .padding(Spacing.large)
                .glassEffect(.regular, in: .circle)
                .accessibilityLabel("Loading")
        default:
            EmptyView()
        }
    }

    /// The handle at the top, like Apple Music's. Swiping down closes the player, and so does
    /// tapping the handle, for anyone who doesn't swipe.
    private var grabber: some View {
        Button { close() } label: {
            Capsule()
                .fill(Palette.textSecondary)
                .frame(width: Layout.grabberWidth, height: Layout.grabberHeight)
                // As tall as the gap above the content, so it never covers a control.
                .frame(width: Layout.grabberHitWidth, height: Spacing.xLarge)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }

    private var pausesWhenClosedNotice: some View {
        Label(
            "Playback pauses when you close the player, as YouTube's Terms of Service require.",
            systemImage: "info.circle"
        )
        .font(Typography.caption)
        .foregroundStyle(Palette.textSecondary)
    }

    /// The iPad panel has no swipe to close, so it keeps a button.
    private var hidePanelButton: some View {
        Button { close() } label: {
            Image(systemName: "sidebar.trailing")
                .glassIconButton()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide Player")
    }

    // MARK: Controls

    /// The song with its ⋯ menu, then everything that drives playback.
    private func mainControls(for track: Track) -> some View {
        VStack(spacing: Spacing.xLarge) {
            HStack(spacing: Spacing.medium) {
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(track.title)
                        .font(Typography.nowPlayingTitle)
                    Text(track.artist)
                        .font(Typography.nowPlayingArtist)
                        .foregroundStyle(Palette.textSecondary)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                headerButtons(for: track)
            }
            playbackControls
            if showsVideo(for: track) {
                pausesWhenClosedNotice
            }
        }
        .padding(.horizontal, Spacing.xLarge)
        .padding(.bottom, Spacing.large)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            mainControlsHeight = height
        }
    }

    /// The lyrics or queue, in the artwork's place.
    @ViewBuilder private func panelBody(_ panel: Panel, for track: Track) -> some View {
        switch panel {
        case .lyrics:
            // No full-screen button: the controls step away by themselves while lyrics play.
            LyricsPanel(track: track)
        case .queue:
            queuePanel(scrollingHeaderFor: track)
        }
    }

    /// The same under the artwork and under the lyrics or queue: callers inset it by `Spacing.xLarge`.
    private var playbackControls: some View {
        VStack(spacing: Spacing.xLarge) {
            NowPlayingScrubber()
            transportControls
            #if os(iOS)
            SystemVolumeSlider()
            #endif
            bottomRow
        }
    }

    /// Large frameless buttons, like Apple Music's.
    private var transportControls: some View {
        HStack {
            Spacer()
            Button { player.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(Typography.transportSecondary)
                    .frame(width: TouchTarget.primary, height: TouchTarget.primary)
            }
            .disabled(!player.hasPrevious)
            .accessibilityLabel("Previous")
            Spacer()
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(Typography.transportPrimary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: TouchTarget.primary, height: TouchTarget.primary)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .sensoryFeedback(.selection, trigger: player.isPlaying)
            Spacer()
            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(Typography.transportSecondary)
                    .frame(width: TouchTarget.primary, height: TouchTarget.primary)
            }
            .disabled(!player.hasNext)
            .accessibilityLabel("Next")
            Spacer()
        }
        .buttonStyle(TransportButtonStyle())
    }

    /// Lyrics, AirPlay and Up Next, grouped in the middle like the row along the bottom of Apple Music.
    private var bottomRow: some View {
        HStack(spacing: Layout.nowPlayingAccessorySpacing) {
            panelButton(.lyrics, title: "Lyrics", systemImage: "quote.bubble")
            #if os(iOS)
            AirPlayButton()
                .scaleEffect(Layout.airPlayIconScale)
                .frame(width: Layout.nowPlayingAccessorySide, height: Layout.nowPlayingAccessorySide)
                .accessibilityLabel("AirPlay")
            #endif
            panelButton(.queue, title: "Up Next", systemImage: "list.bullet")
        }
        .frame(maxWidth: .infinity)
    }

    private func panelButton(_ panel: Panel, title: LocalizedStringKey, systemImage: String) -> some View {
        let isOpen = openPanel == panel
        return Button {
            showPanel(isOpen ? nil : panel)
        } label: {
            Image(systemName: systemImage)
                .symbolVariant(isOpen ? .fill : .none)
                .font(Typography.nowPlayingAccessory)
                .foregroundStyle(isOpen ? Palette.textPrimary : Palette.textSecondary)
                .frame(width: Layout.nowPlayingAccessorySide, height: Layout.nowPlayingAccessorySide)
                .background {
                    if isOpen {
                        Circle().fill(Palette.controlFill)
                    }
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }

    // MARK: Lyrics and queue

    /// Small artwork, the song and its menu above the lyrics or queue; tapping it brings the
    /// artwork back, like Apple Music.
    private func compactHeader(for track: Track) -> some View {
        HStack(spacing: Spacing.medium) {
            if presentation == .sidePanel {
                // The Mac's panel has no artwork view to go back to; the player bar switches views.
                compactSummary(for: track)
            } else {
                Button {
                    showPanel(nil)
                } label: {
                    compactSummary(for: track)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the artwork")
            }
            headerButtons(for: track)
        }
    }

    /// Small artwork when there's no video above it, then the song and artist.
    private func compactSummary(for track: Track) -> some View {
        HStack(spacing: Spacing.medium) {
            if !showsVideo(for: track) {
                if presentation == .sidePanel {
                    ArtworkView(url: track.artworkURL, size: ArtworkSize.row, cornerRadius: Radius.small)
                } else {
                    // Drawn by `movingArtwork`, so it glides here from the full-size artwork.
                    artworkSlot(.compact)
                        .frame(width: ArtworkSize.row, height: ArtworkSize.row)
                        .overlay {
                            if openPanel == .queue {
                                // Loads during the glide (same image, so it's cached), then takes
                                // over so it can scroll away with Up Next's header.
                                ArtworkView(url: track.largeArtworkURL ?? track.artworkURL, cornerRadius: Radius.small)
                                    .opacity(isArtworkGliding ? Opacity.hidden : Opacity.opaque)
                            }
                        }
                }
            }
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(track.title)
                    .font(Typography.headline)
                Text(track.artist)
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            .lineLimit(1)
            Spacer(minLength: Spacing.small)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// The star, which likes the song on YouTube, and the ⋯ menu.
    private func headerButtons(for track: Track) -> some View {
        HStack(spacing: Spacing.none) {
            LikeButton(track: track)
            moreMenu(for: track)
        }
    }

    /// Up Next like Apple Music's queue: the song, then Shuffle, Repeat and Autoplay, then the
    /// songs with handles for dragging them into a new order. Everything above the songs scrolls
    /// away with them. The Mac's panel keeps its song header fixed, so it passes no track.
    private func queuePanel(scrollingHeaderFor track: Track?) -> some View {
        let header = VStack(alignment: .leading, spacing: Spacing.medium) {
            if let track {
                compactHeader(for: track)
                    // Lines up with the song header over the lyrics.
                    .padding(.horizontal, Spacing.xLarge - Spacing.large)
                    .padding(.bottom, Spacing.small)
            }
            queueModeButtons
            SectionHeader(
                title: "Continue Playing",
                actionTitle: player.canEditQueue && !player.upcoming.isEmpty ? "Clear" : nil,
                action: player.canEditQueue ? { player.clearUpNext() } : nil
            )
        }
        .padding(.bottom, Spacing.medium)

        return Group {
            if player.upcoming.isEmpty && !showsAutoplaySection {
                VStack(alignment: .leading, spacing: Spacing.none) {
                    header
                    ContentUnavailableView(
                        "Nothing Up Next",
                        systemImage: "list.bullet",
                        description: Text("Songs queued after this one appear here.")
                    )
                    .frame(maxHeight: .infinity)
                }
            } else {
                #if os(macOS)
                // The Mac's list ignores a top margin for a header to sit over, which would leave
                // the header covering the first songs, so it scrolls as the list's first row.
                upNextList(header: header)
                    .scrollEdgeFade()
                #else
                ScrollAwayHeaderList {
                    header
                } list: {
                    upNextList(header: EmptyView?.none)
                }
                #endif
            }
        }
    }

    private var queueModeButtons: some View {
        HStack(spacing: Spacing.small) {
            QueueModeButton("Shuffle", systemImage: "shuffle", isOn: player.isShuffled) {
                player.toggleShuffle()
            }
            .disabled(!player.supportsShuffleAndRepeat)
            QueueModeButton(
                repeatTitle,
                systemImage: player.repeatMode == .one ? "repeat.1" : "repeat",
                isOn: player.repeatMode != .off
            ) {
                player.cycleRepeatMode()
            }
            .disabled(!player.supportsShuffleAndRepeat)
            QueueModeButton("Autoplay", systemImage: "infinity", isOn: player.isAutoplayEnabled) {
                player.toggleAutoplay()
            }
        }
    }

    private var showsAutoplaySection: Bool {
        player.isAutoplayEnabled && (!player.autoplayUpcoming.isEmpty || player.isFindingAutoplayTracks)
    }

    /// Drag a song by its handle to move it; long-press it to play it next or remove it.
    /// Autoplay's songs follow below a divider, like Apple Music's, and keep their order.
    private func upNextList<Header: View>(header: Header?) -> some View {
        List {
            if let header {
                header
                    .queueRow()
            }
            if player.upcoming.isEmpty {
                Text("Songs you queue play before Autoplay's.")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .queueRow()
            }
            ForEach(player.upcoming) { item in
                upNextRow(item)
                    .queueRow()
            }
            .onMove(perform: moveUpNext)
            #if os(macOS)
            // Delete removes the selected song, as in Apple Music on the Mac.
            .onDelete(perform: removeUpNext)
            #endif

            if showsAutoplaySection {
                autoplayHeader
                    .queueRow()
                ForEach(player.autoplayUpcoming) { item in
                    upNextRow(item)
                        .queueRow()
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        #if os(iOS)
        // Keeps the handles showing, as in Apple Music, without the delete buttons.
        .environment(\.editMode, .constant(player.canEditQueue ? .active : .inactive))
        #endif
    }

    /// A hairline, then the ∞ and what Autoplay is playing, like Apple Music's.
    private var autoplayHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            Divider()
            HStack(alignment: .center, spacing: Spacing.medium) {
                Image(systemName: "infinity")
                    .font(Typography.headline)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: Layout.headerIconSide, height: Layout.headerIconSide)
                    .background(Circle().fill(Palette.controlFill))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text("Autoplay")
                        .font(Typography.sectionTitle)
                    Group {
                        if player.autoplayUpcoming.isEmpty {
                            Text("Finding more music…")
                        } else {
                            Text("Similar music")
                        }
                    }
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if player.isFindingAutoplayTracks && player.autoplayUpcoming.isEmpty {
                    ProgressView()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, Spacing.medium)
    }

    private var repeatTitle: LocalizedStringKey {
        switch player.repeatMode {
        case .off: "Repeat"
        case .all: "Repeat All"
        case .one: "Repeat One"
        }
    }

    /// Tapping plays from that song; the menu moves it up or takes it out.
    private func upNextRow(_ item: QueueItem) -> some View {
        Button { player.jump(to: item.index) } label: {
            #if os(iOS)
            // The drag handle takes the length's place, as in Apple Music.
            TrackRow(track: item.track) { EmptyView() }
            #else
            TrackRow(track: item.track)
            #endif
        }
        .buttonStyle(.plain)
        .contextMenu {
            if player.canEditQueue {
                Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    player.playNext(queuedAt: item.index)
                }
                Button("Remove from Up Next", systemImage: "minus.circle", role: .destructive) {
                    player.removeUpNext(atOffsets: [item.index - (player.currentIndex ?? item.index) - 1])
                }
            }
        }
    }

    /// Only YouTube queues can be edited; nil leaves the list fixed.
    private var moveUpNext: ((IndexSet, Int) -> Void)? {
        guard player.canEditQueue else { return nil }
        return { offsets, destination in player.moveUpNext(fromOffsets: offsets, toOffset: destination) }
    }

    private var removeUpNext: ((IndexSet) -> Void)? {
        guard player.canEditQueue else { return nil }
        return { offsets in player.removeUpNext(atOffsets: offsets) }
    }

    // MARK: Mac panel

    #if os(macOS)
    /// Laid out like the iPhone's lyrics and queue views: the video (YouTube's rules keep it on
    /// screen), the song with its star and ⋯, then the lyrics or Up Next. The player bar's
    /// Lyrics and Up Next buttons switch between them, and it's dark and tinted by the artwork
    /// whatever the Mac's appearance.
    private func sidePanelContent(for track: Track) -> some View {
        VStack(spacing: Spacing.large) {
            if showsVideo(for: track) {
                cover(for: track)
            }
            compactHeader(for: track)
            switch sidePanelMode {
            case .lyrics:
                LyricsPanel(track: track)
            case .upNext:
                queuePanel(scrollingHeaderFor: nil)
            }
            if showsVideo(for: track) {
                pausesWhenClosedNotice
            }
        }
        .padding(Spacing.large)
        .background { backdrop(for: track) }
        .environment(\.colorScheme, .dark)
    }
    #endif

    /// Whether the lyrics are on screen, so the ⋯ menu offers their timing.
    private var areLyricsShowing: Bool {
        #if os(macOS)
        if presentation == .sidePanel { return sidePanelMode == .lyrics }
        #endif
        return isShowingLyrics
    }

    /// YouTube's video shows only when its rules apply. With background play on, the player
    /// stays in its fixed hidden spot (see `MainTabView`) and Now Playing shows artwork instead.
    private func showsVideo(for track: Track) -> Bool {
        track.requiresVisiblePlayer && !isYouTubeBackgroundPlayEnabled
    }

    // MARK: Menu and cover

    private func moreMenu(for track: Track) -> some View {
        Menu {
            Button("Add to Playlist…", systemImage: "text.badge.plus") {
                router.addToPlaylist([track])
            }
            // These open in the tab behind; on iPhone the player closes to show them.
            Button("Go to Album", systemImage: "square.stack") {
                router.showAlbum(for: track)
            }
            Button("Go to Artist", systemImage: "music.mic") {
                router.showArtist(for: track)
            }
            if areLyricsShowing {
                Section("Lyrics Timing") {
                    Button("Show Lyrics Earlier", systemImage: "backward") {
                        lyricsService.adjustOffset(by: -LyricsPolicy.offsetStep, for: track)
                    }
                    Button("Show Lyrics Later", systemImage: "forward") {
                        lyricsService.adjustOffset(by: LyricsPolicy.offsetStep, for: track)
                    }
                    if lyricsService.offset(for: track) != 0 {
                        Button("Reset Timing", systemImage: "arrow.counterclockwise") {
                            lyricsService.setOffset(0, for: track)
                        }
                    }
                }
            }
            ShareLink(item: track.externalURL) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button("Open in \(track.source.appName)", systemImage: "arrow.up.right.square") {
                openExternally(track)
            }
        } label: {
            Image(systemName: "ellipsis")
                .headerIconButton()
        }
        .accessibilityLabel("More")
        #if os(macOS)
        // The Mac draws pull-down chrome around a menu's label; the glass circle is the button.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        #endif
    }

    /// The official player at the video's own 16:9 shape, so YouTube draws no letterbox bars.
    /// It never drops below YouTube's 200 pt minimum height.
    private func cover(for track: Track) -> some View {
        let height = max(Layout.playerMinimumSide, coverContainerWidth / Layout.videoAspectRatio)
        let showsVideo = showsVideo(for: track)
        return ZStack {
            if showsVideo {
                // Taps go nowhere, so YouTube's own overlay never appears; the native controls
                // below drive playback and "Open in YouTube" stays in the ⋯ menu.
                YouTubePlayerView(webView: player.webView, onAttach: { player.webViewDidMove() })
                    .allowsHitTesting(false)
            } else {
                ArtworkView(url: track.largeArtworkURL ?? track.artworkURL, cornerRadius: Radius.none)
            }
            coverOverlay(for: track)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(.rect(cornerRadius: Radius.large))
        .shadow(color: Palette.shadow, radius: Elevation.shadowRadius, y: Elevation.shadowOffsetY)
        // Artwork eases back while paused, like Apple Music; the video stays put.
        .scaleEffect(showsVideo || player.isPlaying || player.status == .loading ? 1 : Layout.pausedArtworkScale)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            coverContainerWidth = width
        }
        .animation(Motion.standard, value: player.status)
    }

    /// Artwork stands in for the player whenever nothing is playing (which also hides YouTube's
    /// own paused-state overlay); the video is never covered mid-song.
    @ViewBuilder private func coverOverlay(for track: Track) -> some View {
        switch player.status {
        case .idle, .loading, .paused, .ended:
            ZStack {
                ArtworkView(url: track.largeArtworkURL ?? track.artworkURL, cornerRadius: Radius.none)
                if player.status == .loading {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Palette.onPlayer)
                        .padding(Spacing.large)
                        .glassEffect(.regular, in: .circle)
                        .accessibilityLabel("Loading")
                }
            }
            .transition(.opacity)
        case .buffering:
            ProgressView()
                .controlSize(.large)
                .tint(Palette.onPlayer)
                .accessibilityLabel("Buffering")
        case .failed(let error):
            ZStack {
                ArtworkView(url: track.largeArtworkURL ?? track.artworkURL, cornerRadius: Radius.none)
                Palette.scrim
                playbackError(error, for: track)
            }
            .transition(.opacity)
        case .playing:
            EmptyView()
        }
    }

    private func playbackError(_ error: AppError, for track: Track) -> some View {
        VStack(spacing: Spacing.medium) {
            Label(error.title, systemImage: error.systemImage)
                .font(Typography.headline)
            Text(error.message)
                .font(Typography.footnote)
                .multilineTextAlignment(.center)
                .opacity(Opacity.secondaryOnMedia)
            VStack(spacing: Spacing.small) {
                if error.isRetryable {
                    Button("Try Again") { player.resume() }
                        .buttonStyle(.glassProminent)
                }
                HStack(spacing: Spacing.small) {
                    if player.hasNext {
                        Button("Skip") { player.next() }
                            .buttonStyle(.glass)
                    }
                    Button("Open in \(track.source.appName)") { openExternally(track) }
                        .buttonStyle(.glass)
                }
            }
            .controlSize(.small)
        }
        .foregroundStyle(Palette.onPlayer)
        .padding(Spacing.large)
    }

    /// The artwork's own colors, deepened, under white text, like Apple Music.
    private func backdrop(for track: Track) -> some View {
        ZStack {
            Palette.playerBackground
            ArtworkView(url: track.largeArtworkURL ?? track.artworkURL, cornerRadius: Radius.none)
                .blur(radius: BlurRadius.backdrop, opaque: true)
                .saturation(ColorAdjustment.backdropSaturation)
            Palette.backdropDim
        }
        .ignoresSafeArea()
        // Only a backdrop: it never takes clicks or taps meant for what's in front or beside it.
        .allowsHitTesting(false)
    }

    private func close() {
        switch presentation {
        case .fullScreen: dismiss()
        case .panel, .sidePanel: player.isNowPlayingPresented = false
        }
    }

    private func openExternally(_ track: Track) {
        player.pause()
        openURL(track.externalURL)
    }
}

/// Apple Music's scrubber: a thin bar that thickens while dragged, with the times underneath.
/// Dragging moves from where the song is rather than jumping to the finger, so it can be fine-tuned.
/// What restarts the countdown that hides the controls over lyrics.
private struct ControlsCountdown: Equatable {
    let isRunning: Bool
    let reveals: Int
}

/// Where Now Playing's artwork sits: full size above the controls, or small beside the song.
private enum ArtworkSlot: Hashable {
    case immersive
    case compact
}

/// The artwork slots on screen, so one artwork view can be drawn in whichever is showing.
private struct ArtworkSlotKey: PreferenceKey {
    static let defaultValue: [ArtworkSlot: Anchor<CGRect>] = [:]

    static func reduce(value: inout [ArtworkSlot: Anchor<CGRect>], nextValue: () -> [ArtworkSlot: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, next in next }
    }
}

/// A list whose header scrolls away with it, like Apple Music's Up Next. The header sits over the
/// list's top margin and moves up as the songs scroll. It keeps its own scroll state, so
/// scrolling redraws only this, not Now Playing around it. iPhone and iPad only: the Mac's list
/// ignores the margin.
private struct ScrollAwayHeaderList<Header: View, Content: View>: View {
    @ViewBuilder let header: Header
    @ViewBuilder let list: Content

    @State private var headerHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        list
            .contentMargins(.top, headerHeight, for: .scrollContent)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                scrollOffset = offset
            }
            .overlay(alignment: .top) {
                header
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        headerHeight = height
                    }
                    // Pulling down past the top leaves the header where it is.
                    .offset(y: -max(0, scrollOffset))
            }
            .scrollEdgeFade()
    }
}

/// Content melts away at a scroll view's edge only while there's more past it, so a list never
/// looks cut off and stays clear at rest. Keeps its own state, so scrolling redraws only this.
private struct ScrollEdgeFade: ViewModifier {
    @State private var overflow = ScrollOverflow()

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: ScrollOverflow.self) { geometry in
                ScrollOverflow(
                    above: geometry.visibleRect.minY > geometry.contentInsets.top * -1,
                    below: geometry.visibleRect.maxY < geometry.contentSize.height
                )
            } action: { _, newOverflow in
                withAnimation(Motion.quick) { overflow = newOverflow }
            }
            .edgeFade(
                top: overflow.above ? Layout.queueEdgeFade : 0,
                bottom: overflow.below ? Layout.queueEdgeFade : 0
            )
    }
}

private extension View {
    func scrollEdgeFade() -> some View {
        modifier(ScrollEdgeFade())
    }

    /// Up Next's rows sit straight on Now Playing's background, without separators.
    func queueRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(
                top: Spacing.small, leading: Spacing.none, bottom: Spacing.small, trailing: Spacing.none
            ))
    }
}

/// Whether a scroll view has content past its top or bottom edge.
private struct ScrollOverflow: Equatable {
    var above = false
    var below = false
}

/// Reads the playback position itself. It changes several times a second, and read anywhere in
/// Now Playing's body it would redraw everything around it, making an open ⋯ menu flicker.
private struct NowPlayingScrubber: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        PlaybackScrubber(position: player.currentTime, duration: player.duration, onSeek: player.seek(to:))
    }
}

private struct PlaybackScrubber: View {
    let position: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var dragStart: TimeInterval?
    @State private var dragPosition: TimeInterval?

    private var isDragging: Bool { dragPosition != nil }
    private var shownPosition: TimeInterval { dragPosition ?? position }

    private var fraction: Double {
        duration > 0 ? min(1, max(0, shownPosition / duration)) : 0
    }

    var body: some View {
        VStack(spacing: Spacing.xSmall) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Palette.inactive)
                    Capsule()
                        .fill(isDragging ? Palette.textPrimary : Palette.textSecondary)
                        .frame(width: proxy.size.width * fraction)
                }
                .frame(height: isDragging ? Layout.scrubberActiveHeight : Layout.scrubberHeight)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0, proxy.size.width > 0 else { return }
                            let start = dragStart ?? position
                            dragStart = start
                            let moved = value.translation.width / proxy.size.width * duration
                            dragPosition = min(duration, max(0, start + moved))
                        }
                        .onEnded { _ in
                            // A tap without a drag leaves the song where it is.
                            if let dragPosition, dragPosition != dragStart { onSeek(dragPosition) }
                            dragPosition = nil
                            dragStart = nil
                        }
                )
            }
            .frame(height: Layout.scrubberHitHeight)

            HStack {
                Text(TimeFormatting.string(from: shownPosition))
                Spacer()
                Text("-\(TimeFormatting.string(from: max(0, duration - shownPosition)))")
            }
            .font(Typography.monospacedCaption)
            .foregroundStyle(isDragging ? Palette.textPrimary : Palette.textSecondary)
        }
        .animation(Motion.quick, value: isDragging)
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

/// Frameless playback buttons, like Apple Music's: a soft circle and a slight shrink while
/// pressed, and dimmed when there's nothing to skip to.
private struct TransportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TransportButtonLabel(configuration: configuration)
    }
}

private struct TransportButtonLabel: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .foregroundStyle(isEnabled ? Palette.textPrimary : Palette.textDisabled)
            .background {
                Circle()
                    .fill(Palette.controlFill)
                    .opacity(configuration.isPressed ? Opacity.opaque : Opacity.hidden)
            }
            .scaleEffect(configuration.isPressed ? Layout.pressedControlScale : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// Shuffle and Repeat above the queue, like Apple Music's: a capsule that turns solid while on.
private struct QueueModeButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let isOn: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: LocalizedStringKey, systemImage: String, isOn: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isOn = isOn
        self.action = action
    }

    private var foreground: Color {
        // The solid capsule is the text color, so its icon takes the background's.
        if isOn { return Palette.surface }
        return isEnabled ? Palette.textPrimary : Palette.textDisabled
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(Typography.headline)
                .foregroundStyle(foreground)
                .contentTransition(.symbolEffect(.replace))
                .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum)
                .background(Capsule().fill(isOn ? Palette.textPrimary : Palette.controlFill))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Apple Music's star, which here likes the song on YouTube. It shows only where that can work:
/// a YouTube video, with an account connected.
private struct LikeButton: View {
    let track: Track
    @Environment(YouTubeLikes.self) private var likes
    @State private var likeError: AppError?

    var body: some View {
        if likes.canLike(track) {
            let isLiked = likes.isLiked(track)
            Button {
                Task {
                    do {
                        try await likes.toggle(track)
                    } catch {
                        if !error.isCancellation { likeError = AppError(error) }
                    }
                }
            } label: {
                Image(systemName: isLiked ? "star.fill" : "star")
                    .headerIconButton()
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLiked ? "Remove Like" : "Like on YouTube")
            .sensoryFeedback(.selection, trigger: isLiked)
            .task(id: track.id) { await likes.load(track) }
            .errorAlert($likeError)
        }
    }
}

private extension Image {
    /// Apple Music's small filled circle, for the star and ⋯ beside the song, in a full-size
    /// tap area.
    func headerIconButton() -> some View {
        self
            .font(Typography.headerIcon)
            .foregroundStyle(Palette.textPrimary)
            .frame(width: Layout.headerIconSide, height: Layout.headerIconSide)
            .background(Circle().fill(Palette.controlFill))
            .frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
            .contentShape(.circle)
    }

    /// A 44 pt Liquid Glass circle, the standard tap size for Now Playing's round buttons.
    func glassIconButton() -> some View {
        self
            .font(Typography.headline)
            .foregroundStyle(Palette.textPrimary)
            .frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
            .contentShape(.circle)
            .glassEffect(.regular.interactive(), in: .circle)
    }
}
