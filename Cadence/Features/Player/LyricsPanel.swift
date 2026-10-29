import SwiftUI

/// Lyrics for the current track, fetched only while the panel is open.
struct LyricsPanel: View {
    let track: Track

    @Environment(LyricsService.self) private var lyricsService
    @Environment(PlayerController.self) private var player
    @State private var lyrics: LoadState<Lyrics?> = .idle
    @State private var loadedTrackID: Track.ID?

    /// The length of what's actually playing, once the player reports it, to the second.
    private var playingDuration: TimeInterval? {
        player.duration > 0 ? player.duration.rounded() : track.duration?.rounded()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: LyricsRequest(trackID: track.id, duration: playingDuration)) {
                // A new song starts from scratch; a corrected length quietly re-picks the lyrics.
                if loadedTrackID != track.id {
                    lyrics = .idle
                    loadedTrackID = track.id
                }
                await load()
            }
    }

    @ViewBuilder private var content: some View {
        switch lyrics {
        case .idle, .loading:
            VStack(spacing: Spacing.medium) {
                ProgressView()
                Text("Finding lyrics…")
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
        case .failed(let error):
            ContentUnavailableView {
                Label(error.title, systemImage: error.systemImage)
            } description: {
                Text(error.message)
            } actions: {
                if error.isRetryable {
                    Button("Try Again", systemImage: "arrow.clockwise") {
                        Task { await load() }
                    }
                    .buttonStyle(.glass)
                }
            }
        case .loaded(.none):
            ContentUnavailableView(
                "No Lyrics Found",
                systemImage: "quote.bubble",
                description: Text("LRCLIB doesn't have lyrics for this song yet.")
            )
        case .loaded(.instrumental):
            ContentUnavailableView(
                "Instrumental",
                systemImage: "music.note",
                description: Text("This track has no lyrics.")
            )
        case .loaded(.plain(let text)):
            stillLyrics(text, note: "These lyrics aren't time-synced.")
        case .loaded(.synced(let lines)) where track.isMusicVideo:
            // Music videos' intros and skits throw the timing off, so the lyrics hold still.
            stillLyrics(
                lines.map(\.text).joined(separator: "\n"),
                note: "Lyrics hold still during music videos. Switch to Song to follow along."
            )
        case .loaded(.synced(let lines)):
            SyncedLyricsView(
                lines: lines,
                currentTime: player.currentTime,
                isPlaying: player.isPlaying,
                offset: lyricsService.offset(for: track),
                onSeek: { time in player.seek(to: max(0, time)) },
                onSyncLine: { line in
                    lyricsService.setOffset(player.currentTime - line.time, for: track)
                }
            )
        }
    }

    /// Lyrics as one block of text to scroll through, with no line following the song.
    private func stillLyrics(_ text: String, note: LocalizedStringKey) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                Label(note, systemImage: "info.circle")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                Text(text)
                    .font(Typography.plainLyrics)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Layout.lyricsEdgeFade)
        }
        .scrollIndicators(.hidden)
        .lyricsEdgeFade()
    }

    private func load() async {
        await refreshContent($lyrics) { try await lyricsService.lyrics(for: track, duration: playingDuration) }
    }
}

private struct LyricsRequest: Equatable {
    let trackID: Track.ID
    let duration: TimeInterval?
}

private extension View {
    /// Fades lines out at the top and bottom of the panel instead of clipping them hard.
    func lyricsEdgeFade() -> some View {
        edgeFade(length: Layout.lyricsEdgeFade)
    }
}

/// Moves the lyrics like Apple Music when they advance. The scroll jumps straight to the new line
/// and every line starts back where it was, then glides up on its own spring: the new line and
/// the ones already sung together, then each line below a moment after the one above it.
/// No line ever moves down.
private struct LyricFollowTrail: ViewModifier {
    let follow: LyricFollow?
    let trigger: Int

    func body(content: Content) -> some View {
        let start = follow?.start ?? 0
        let delay = follow?.delay ?? 0
        return content.keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { view, offset in
            view.offset(y: offset)
        } keyframes: { _ in
            KeyframeTrack {
                MoveKeyframe(start)
                // A zero-length hold stalls the track and leaves the line stuck where it started.
                if delay > 0 {
                    LinearKeyframe(start, duration: delay)
                    SpringKeyframe(0, spring: LyricMotion.followSpring)
                } else {
                    SpringKeyframe(0, spring: LyricMotion.followSpring)
                }
            }
        }
    }
}

/// One line's part in an advance: it starts `start` points below where it belongs and springs
/// into place after `delay`.
private struct LyricFollow {
    let start: CGFloat
    let startedAt: Date
    let delay: TimeInterval

    /// The new line and those above it move at once; each line below waits a little longer.
    init(start: CGFloat, linesFromActive: Int, at date: Date) {
        self.start = start
        startedAt = date
        let order = min(max(linesFromActive, 0), LyricMotion.maxTrailingLines)
        delay = Double(order) * LyricMotion.followDelayPerLine
    }

    /// How far the line still is from where it belongs, so a quick next advance carries on from
    /// there instead of snapping it into place first.
    func remaining(at date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSince(startedAt) - delay
        guard elapsed > 0 else { return start }
        return start * (1 - LyricMotion.followSpring.value(target: 1, time: elapsed))
    }
}

/// Line heights, the scroll position and each line's follow motion. A plain class, so updating
/// it as the lyrics scroll never redraws them.
private final class LyricScrollMetrics {
    var lineHeights: [LyricLine.ID: CGFloat] = [:]
    /// The top of the visible area, in the lyrics' own coordinates.
    var visibleTop: CGFloat = 0
    var follows: [LyricLine.ID: LyricFollow] = [:]
}

/// Lights a line up glyph by glyph in reading order, following wrapped lines, with a soft
/// edge between sung and unsung text. Longer words have more glyphs, so they take longer.
private struct LyricSweepRenderer: TextRenderer {
    var progress: Double
    var sungOpacity: Double
    var unsungOpacity: Double

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(progress, AnimatablePair(sungOpacity, unsungOpacity)) }
        set {
            progress = newValue.first
            sungOpacity = newValue.second.first
            unsungOpacity = newValue.second.second
        }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let glyphs = layout.flatMap { line in line }.flatMap { run in run }
        let count = Double(max(glyphs.count, 1))
        let edge = LyricMotion.sweepEdgeGlyphs / count
        for (index, glyph) in glyphs.enumerated() {
            let position = Double(index) / count
            // 0 before the sweep reaches this glyph, 1 once it has fully passed.
            let lit = min(max((progress * (1 + edge) - position) / edge, 0), 1)
            var glyphContext = context
            glyphContext.opacity = unsungOpacity + (sungOpacity - unsungOpacity) * lit
            glyphContext.draw(glyph)
        }
    }
}

/// Apple Music–style lyrics: the line being sung is bright, sharp and kept near the top; other
/// lines dim and blur progressively with distance from it. Everything sharpens while paused or scrolling,
/// and auto-scrolling picks up again at the next line.
private struct SyncedLyricsView: View {
    let lines: [LyricLine]
    let currentTime: TimeInterval
    /// Lines only blur while the song plays; paused lyrics are all sharp and easy to read.
    let isPlaying: Bool
    /// Shifts every line; positive values show lyrics later (for videos with intros).
    let offset: TimeInterval
    let onSeek: (TimeInterval) -> Void
    let onSyncLine: (LyricLine) -> Void

    @AppStorage(StorageKey.wordByWordLyrics) private var isWordSweepEnabled = false
    @State private var isUserScrolling = false
    /// Bumped on every automatic advance; replays the trailing animation on each line.
    @State private var followCount = 0
    @State private var metrics = LyricScrollMetrics()
    @State private var viewportHeight: CGFloat = 0

    private let focusAnchor = UnitPoint(x: 0.5, y: Layout.lyricsFocus)

    private var bottomFade: CGFloat {
        max(Layout.lyricsEdgeFade, viewportHeight * Layout.lyricsBottomFadeFraction)
    }

    /// Space above the first line and below the last, so even the opening and closing lines can
    /// glide to the focus position like the rest instead of the list sitting still.
    private var topRunway: CGFloat {
        max(Layout.lyricsEdgeFade, viewportHeight * Layout.lyricsFocus)
    }

    private var bottomRunway: CGFloat {
        max(bottomFade, viewportHeight * (1 - Layout.lyricsFocus))
    }

    /// Advances slightly early so the glide lands as the line is sung, making up for the
    /// player's position updates arriving in steps and a little late.
    private var activeLineID: LyricLine.ID? {
        let leadTime = currentTime + LyricsPolicy.highlightLead
        return lines.last { $0.time + offset <= leadTime }?.id
    }

    /// How far the sweep has moved through `line`, from 0 to 1. Sung lines stay at 1 and simply
    /// dim, so finishing a line never plays the sweep backwards.
    private func sweepProgress(for line: LyricLine, activeLineID: LyricLine.ID?) -> Double {
        // With the feature off every line stays at 1, so nothing ever animates as a sweep;
        // the current line just fades up as a whole.
        guard isWordSweepEnabled else { return 1 }
        guard let activeLineID, line.id <= activeLineID else { return 0 }
        guard line.id == activeLineID, !line.text.isEmpty else { return 1 }
        let elapsed = currentTime + LyricsPolicy.highlightLead - (line.time + offset)
        return min(max(elapsed / line.sweepDuration, 0), 1)
    }

    /// Line IDs are their positions, so the distance between IDs is the distance in lines.
    private func blurRadius(for line: LyricLine, activeLineID: LyricLine.ID?) -> CGFloat {
        guard isPlaying, !isUserScrolling else { return 0 }
        let distance = abs(line.id - (activeLineID ?? 0))
        return min(CGFloat(distance) * BlurRadius.lyricStep, BlurRadius.lyricMaximum)
    }

    /// How far the lyrics must scroll to bring `lineID` to the focus position, matching what
    /// `scrollTo(_:anchor:)` does with `focusAnchor`. Nil until every line up to it is measured.
    private func distanceToFocus(of lineID: LyricLine.ID) -> CGFloat? {
        var top = topRunway
        for line in lines {
            guard let height = metrics.lineHeights[line.id] else { return nil }
            if line.id == lineID {
                return top + height * Layout.lyricsFocus - (metrics.visibleTop + viewportHeight * Layout.lyricsFocus)
            }
            top += height + Layout.lyricsLineSpacing
        }
        return nil
    }

    var body: some View {
        let activeLineID = activeLineID
        ScrollViewReader { proxy in
            ScrollView {
                // Not lazy: the follow animation needs every line's height, and songs are short.
                VStack(alignment: .leading, spacing: Layout.lyricsLineSpacing) {
                    ForEach(lines) { line in
                        let isActive = line.id == activeLineID
                        let blur = blurRadius(for: line, activeLineID: activeLineID)
                        let sweep = sweepProgress(for: line, activeLineID: activeLineID)
                        Button {
                            onSeek(line.time + offset)
                        } label: {
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(Typography.lyric)
                                .foregroundStyle(Palette.textPrimary)
                                .textRenderer(LyricSweepRenderer(
                                    progress: sweep,
                                    sungOpacity: isActive ? Opacity.opaque : Opacity.inactiveLyric,
                                    unsungOpacity: isActive && isWordSweepEnabled ? Opacity.unsungLyric : Opacity.inactiveLyric
                                ))
                                // Position updates arrive in steps; easing linearly between them
                                // keeps the sweep moving continuously.
                                .animation(.linear(duration: PlaybackPolicy.progressInterval), value: sweep)
                                .blur(radius: blur)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .animation(Motion.standard, value: isActive)
                        .animation(Motion.standard, value: blur)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            metrics.lineHeights[line.id] = height
                        }
                        .modifier(LyricFollowTrail(follow: metrics.follows[line.id], trigger: followCount))
                        .contextMenu {
                            Button("Sync This Line to Now", systemImage: "metronome") {
                                onSyncLine(line)
                            }
                        }
                        .accessibilityAddTraits(isActive ? .isSelected : [])
                        .accessibilityHint("Plays from this line")
                        .id(line.id)
                    }
                }
                .padding(.top, topRunway)
                .padding(.bottom, bottomRunway)
                // Room for blurred lines to spread sideways without being clipped.
                .padding(.horizontal, BlurRadius.lyricOverflow)
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.containerSize.height
            } action: { _, height in
                viewportHeight = height
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.visibleRect.minY
            } action: { _, top in
                metrics.visibleTop = top
            }
            // Upcoming lines fade out gently toward the bottom, as in Apple Music.
            .edgeFade(top: Layout.lyricsEdgeFade, bottom: bottomFade)
            // Lets that room reach past the panel's edge, so the text itself stays aligned.
            .padding(.horizontal, -BlurRadius.lyricOverflow)
            .onScrollPhaseChange { _, newPhase in
                // Only touch-driven phases count. Our own animated scrolls report `.animating`,
                // which doesn't always return to `.idle`, so counting it would stop auto-scrolling.
                switch newPhase {
                case .tracking, .interacting, .decelerating:
                    isUserScrolling = true
                default:
                    isUserScrolling = false
                }
            }
            .onChange(of: activeLineID) { _, newLineID in
                guard let newLineID, !isUserScrolling else { return }
                // Line-by-line advances move as a chain; seeks and long jumps simply glide there.
                guard let distance = distanceToFocus(of: newLineID), distance > 0, distance < viewportHeight else {
                    withAnimation(Motion.lyricFollow) {
                        proxy.scrollTo(newLineID, anchor: focusAnchor)
                    }
                    return
                }
                let now = Date.now
                for line in lines {
                    let remaining = metrics.follows[line.id]?.remaining(at: now) ?? 0
                    metrics.follows[line.id] = LyricFollow(
                        start: remaining + distance,
                        linesFromActive: line.id - newLineID,
                        at: now
                    )
                }
                // Unanimated, so the jump lands in the same frame that offsets every line back.
                followCount += 1
                proxy.scrollTo(newLineID, anchor: focusAnchor)
            }
            .onAppear {
                if let activeLineID {
                    proxy.scrollTo(activeLineID, anchor: focusAnchor)
                }
            }
            .onChange(of: viewportHeight) {
                // The runway changes with the view's height; keep the sung line where it was.
                if let activeLineID, !isUserScrolling {
                    proxy.scrollTo(activeLineID, anchor: focusAnchor)
                }
            }
        }
    }
}
