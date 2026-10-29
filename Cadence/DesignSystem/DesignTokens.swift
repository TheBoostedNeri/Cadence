import SwiftUI

/// Spacing scale for padding, stack spacing and insets.
enum Spacing {
    static let none: CGFloat = 0
    static let xxSmall: CGFloat = 2
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 24
    static let xxLarge: CGFloat = 32
    static let xxxLarge: CGFloat = 48
}

/// Corner radii for rounded rectangles.
enum Radius {
    static let none: CGFloat = 0
    static let small: CGFloat = 6
    static let medium: CGFloat = 12
    static let large: CGFloat = 20
    static let xLarge: CGFloat = 32
}

/// Fixed icon dimensions for decorative symbols.
enum IconSize {
    static let large: CGFloat = 32
    static let xLarge: CGFloat = 56
    static let hero: CGFloat = 96
    /// Now Playing's Play and Pause, large and frameless like Apple Music's.
    static let transportPrimary: CGFloat = 44
    static let transportSecondary: CGFloat = 30
}

/// Square artwork sizes.
enum ArtworkSize {
    static let mini: CGFloat = 32
    /// The song's artwork in the Mac player bar.
    static let playerBar: CGFloat = 40
    static let row: CGFloat = 52
    static let card: CGFloat = 156
    /// Cards in regular-width windows, like iPad, where people view the screen from further away.
    static let cardLarge: CGFloat = 196
    static let header: CGFloat = 220
    /// The latest release card on an artist's page.
    static let latestRelease: CGFloat = 96
}

/// Minimum hit areas for tappable controls.
enum TouchTarget {
    static let minimum: CGFloat = 44
    static let secondary: CGFloat = 56
    static let primary: CGFloat = 76
}

enum Layout {
    /// YouTube API Services policy: the embedded player viewport must be at least 200×200.
    static let playerMinimumSide: CGFloat = 200
    static let videoAspectRatio: CGFloat = 16.0 / 9.0
    /// The off-screen spot the YouTube player waits in while Now Playing is closed.
    static let hiddenPlayerSide: CGFloat = 1
    /// Artwork eases back to this size while paused, as in Apple Music.
    static let pausedArtworkScale: CGFloat = 0.85
    /// Full-bleed Now Playing artwork is as tall as it is wide, but never takes more than this
    /// share of the screen, so the controls stay in view on short screens.
    static let immersiveArtworkMaxHeightFraction: CGFloat = 0.55
    /// The bottom share of full-bleed artwork that fades into the backdrop.
    static let immersiveArtworkFadeFraction: CGFloat = 0.35
    /// The artwork gives up height so the controls fit, down to this share of Now Playing.
    static let immersiveArtworkMinHeightFraction: CGFloat = 0.25
    /// Fits a two-digit chart position so every row's artwork lines up.
    static let chartRankWidth: CGFloat = 28
    /// Album track numbers line up the same way.
    static let trackNumberWidth: CGFloat = chartRankWidth
    /// Height of the soft fade at the top and bottom of the lyrics.
    static let lyricsEdgeFade: CGFloat = 48
    /// Generous gaps between synced lyric lines, so each stands on its own, as in Apple Music.
    static let lyricsLineSpacing: CGFloat = Spacing.xxxLarge
    /// Where the line being sung sits, as a fraction of the lyrics' height: near the top, like
    /// Apple Music, so upcoming lines get most of the room.
    static let lyricsFocus: CGFloat = 0.25
    /// Upcoming lines fade out over this fraction of the lyrics' height.
    static let lyricsBottomFadeFraction: CGFloat = 0.3
    /// Height of the fade where Now Playing's scrolling content meets the video.
    static let scrollEdgeFade: CGFloat = 32
    static let readableContentWidth: CGFloat = 560
    /// Narrowest column in song grids, so iPhone keeps one column and wide iPad windows get several.
    static let trackGridMinColumnWidth: CGFloat = 320
    /// The playlist's artwork and actions beside its songs in regular-width windows.
    static let detailHeaderColumnWidth: CGFloat = 340
    /// An artist's header is as tall as the page is wide, up to this share of its height.
    static let artistHeaderMaxHeightFraction: CGFloat = 0.5
    /// Songs swiped through in columns, like Apple Music's Top Songs: four to a column.
    static let songColumnRows = 4
    /// How many songs an artist's Top Songs and Discover's Trending show before See All.
    static let songColumnsShown = 20
    /// Discover's genre tiles: as many across as fit at this width.
    static let genreTileMinWidth: CGFloat = 160
    static let genreTileHeight: CGFloat = 96
    /// How much of the next column or card shows, so a row clearly scrolls.
    static let carouselPeek: CGFloat = 32
    /// Song columns in regular-width windows, where several fit side by side.
    static let wideSongColumnWidth: CGFloat = 360
    /// The Now Playing panel beside the app on iPad and Mac.
    static let nowPlayingPanelWidth: CGFloat = 380
    /// The Mac window fits the sidebar, the player bar at its narrowest and the Now Playing panel.
    static let macWindowMinWidth: CGFloat = 1_040
    static let macWindowMinHeight: CGFloat = 640
    static let macWindowDefaultWidth: CGFloat = 1_280
    static let macWindowDefaultHeight: CGFloat = 820
    static let macSettingsWidth: CGFloat = 520
    static let macSettingsHeight: CGFloat = 640
    /// The Mac's floating player bar, like Apple Music's.
    static let macPlayerBarHeight: CGFloat = 56
    /// The song in the middle of the Mac player bar, at most; it narrows with the window, and
    /// Shuffle and Repeat step aside before it gets narrower than the minimum.
    static let macDisplayWidth: CGFloat = 400
    static let macDisplayMinWidth: CGFloat = 200
    static let displayProgressHeight: CGFloat = 3
    /// The progress bar is thin, but takes clicks a little above and below it.
    static let displayProgressHitHeight: CGFloat = 8
    static let macVolumeSliderWidth: CGFloat = 96
    static let buttonMaxWidth: CGFloat = 320
    static let stateMinimumHeight: CGFloat = 320
    static let placeholderSymbolScale: CGFloat = 0.4
    static let cardTitleLineLimit = 2
    /// Now Playing's scrubber is a thin bar that thickens while dragged, like Apple Music's.
    static let scrubberHeight: CGFloat = 6
    static let scrubberActiveHeight: CGFloat = 12
    /// The scrubber takes touches a little above and below the bar.
    static let scrubberHitHeight: CGFloat = 28
    /// The handle at the top of Now Playing, the system grabber's size.
    static let grabberWidth: CGFloat = 36
    static let grabberHeight: CGFloat = 5
    /// The handle takes taps across a wider strip than it draws.
    static let grabberHitWidth: CGFloat = 88
    /// Up Next fades out over this much at an edge with more songs past it.
    static let queueEdgeFade: CGFloat = 32
    /// Lyrics, AirPlay and Up Next along the bottom of Now Playing: grouped toward the middle,
    /// like Apple Music's, rather than pushed to the edges.
    static let nowPlayingAccessorySide: CGFloat = 50
    static let nowPlayingAccessorySpacing: CGFloat = 52
    /// The system draws the AirPlay icon at a fixed size; this brings it up to match the others.
    static let airPlayIconScale: CGFloat = 1.15
    /// The strip along the bottom of the lyrics that brings hidden controls back when tapped.
    static let controlsRevealHeight: CGFloat = 160
    /// The star and ⋯ beside the song in Now Playing, as small as Apple Music's.
    static let headerIconSide: CGFloat = 32
    /// Now Playing's frameless buttons shrink slightly while pressed.
    static let pressedControlScale: CGFloat = 0.88
    static let stepIndicatorDot: CGFloat = 8
    static let stepIndicatorActiveWidth: CGFloat = 24
}

/// Grid columns that grow from one column on iPhone to several in wide iPad windows.
enum GridColumns {
    static let tracks = [
        GridItem(.adaptive(minimum: Layout.trackGridMinColumnWidth), spacing: Spacing.xLarge, alignment: .leading)
    ]
    static let cards = [
        GridItem(.adaptive(minimum: ArtworkSize.cardLarge), spacing: Spacing.xLarge, alignment: .top)
    ]
}

enum Opacity {
    static let hidden: Double = 0
    static let opaque: Double = 1
    static let inactive: Double = 0.3
    /// Options that can't be chosen yet.
    static let unavailable: Double = 0.5
    /// Nearly invisible but still rendered, so WebKit keeps the hidden player running.
    static let hiddenPlayer: Double = 0.01
    /// Lyric lines that aren't being sung right now.
    static let inactiveLyric: Double = 0.35
    /// Words on the current line that the sweep hasn't reached yet.
    static let unsungLyric: Double = 0.55
    static let tint: Double = 0.25
    static let scrim: Double = 0.6
    /// Secondary text drawn over video or artwork.
    static let secondaryOnMedia: Double = 0.85
    static let shadow: Double = 0.18
    /// The translucent circles and capsules behind Now Playing's buttons.
    static let controlFill: Double = 0.14
    /// Darkens Now Playing's artwork-colored background so white text stays readable.
    static let backdropDim: Double = 0.3
    /// The large symbol tucked into a genre tile's corner.
    static let genreSymbol: Double = 0.35
}

enum Elevation {
    static let shadowRadius: CGFloat = 24
    static let shadowOffsetY: CGFloat = 10
}

/// How the lyrics move when they advance to the next line.
enum LyricMotion {
    /// Each line follows the one above it this much later, so the lyrics move as a chain.
    static let followDelayPerLine: TimeInterval = 0.05
    /// Lines further below the sung one than this all share the last delay.
    static let maxTrailingLines = 5
    /// A soft spring with a touch of overshoot, like Apple Music's lyrics.
    static let followSpring = Spring(mass: 0.9, stiffness: 90, damping: 15)
    /// Width of the soft edge between sung and unsung text, in glyphs.
    static let sweepEdgeGlyphs: Double = 3
}

/// Color treatments applied to images.
enum ColorAdjustment {
    /// Now Playing's background deepens the artwork's colors, like Apple Music.
    static let backdropSaturation: Double = 1.5
}

enum BlurRadius {
    static let backdrop: CGFloat = 60
    /// Extra blur per line of distance from the lyric being sung, kept subtle so nearby lines
    /// stay readable.
    static let lyricStep: CGFloat = 0.8
    static let lyricMaximum: CGFloat = 3
    /// Blur spreads past the text by about twice its radius; lyrics leave that much room.
    static let lyricOverflow: CGFloat = lyricMaximum * 2
}

enum Motion {
    static let standard: Animation = .spring(duration: 0.4, bounce: 0.15)
    static let quick: Animation = .easeOut(duration: 0.2)
    /// The lyrics glide to the next line on a soft, slightly longer spring.
    static let lyricFollow: Animation = .spring(duration: 0.6, bounce: 0.12)
    /// How long a success checkmark stays visible before a sheet closes.
    static let confirmationHold: Duration = .milliseconds(600)
    /// How long the controls stay over playing lyrics, untouched, before stepping away.
    static let controlsAutoHideDelay: Duration = .seconds(4)
}
