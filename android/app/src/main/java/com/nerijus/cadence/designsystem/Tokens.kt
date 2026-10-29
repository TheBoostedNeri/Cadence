package com.nerijus.cadence.designsystem

import androidx.compose.animation.core.spring
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

// The same scales as the iPhone and Mac app (Cadence/DesignSystem/DesignTokens.swift), so both
// apps space and round things alike. Screens use these instead of raw numbers.

/** Spacing scale for padding, stack spacing and insets. */
object Spacing {
    val none = 0.dp
    val xxSmall = 2.dp
    val xSmall = 4.dp
    val small = 8.dp
    val medium = 12.dp
    val large = 16.dp
    val xLarge = 24.dp
    val xxLarge = 32.dp
    val xxxLarge = 48.dp
}

/** Corner radii for rounded rectangles. */
object Radius {
    val none = 0.dp
    val small = 6.dp
    val medium = 12.dp
    val large = 20.dp
    val xLarge = 32.dp
}

/** Fixed icon dimensions for decorative symbols. */
object IconSize {
    val large = 32.dp
    val xLarge = 56.dp
    val hero = 96.dp
    /** Now Playing's Play and Pause, large and frameless like Apple Music's. */
    val transportPrimary = 56.dp
    val transportSecondary = 40.dp
}

/** Square artwork sizes. */
object ArtworkSize {
    val mini = 32.dp
    val large = 96.dp
    val row = 48.dp
    val card = 156.dp
    /** Cards in wide windows, like tablets, where people view the screen from further away. */
    val cardLarge = 196.dp
    val header = 220.dp
    /** The latest release card on an artist's page. */
    val latestRelease = 96.dp
    /** The song's artwork beside it over the lyrics and Up Next, when there's no video. */
    val compactHeader = 56.dp
}

/** Minimum touch targets. */
object TouchTarget {
    val minimum = 48.dp
    val secondary = 56.dp
    val primary = 76.dp
}

/** How far raised surfaces, like the mini player, stand off the page. */
object Elevation {
    val raised = 4.dp
}

object Opacity {
    const val inactive = 0.3f
    /** Options that can't be chosen yet. */
    const val unavailable = 0.5f
    /** Secondary text drawn over video or artwork. */
    const val secondaryOnMedia = 0.85f
    /** The scrubber's unplayed part over Now Playing's backdrop. */
    const val scrubberTrack = 0.3f
    /** Behind the Song and Video switch over Now Playing's backdrop; its choice uses `scrubberTrack`. */
    const val switchTrack = 0.15f
    /** Darkens Now Playing's artwork-colored background so white text stays readable. */
    const val backdropDim = 0.45f
    const val opaque = 1f
    /** Lyric lines that aren't being sung right now. */
    const val inactiveLyric = 0.35f
    /** Words on the current line that the sweep hasn't reached yet. */
    const val unsungLyric = 0.55f
    /** The translucent circles behind Now Playing's buttons. */
    const val controlFill = 0.14f
    /** The large symbol tucked into a genre tile's corner. */
    const val genreSymbol = 0.35f
    /** Keeps an artist's name readable on light artwork. */
    const val scrim = 0.6f
    /** Genre tiles deepen toward the bottom, like the iPhone app's color gradients. */
    const val genreTileBottom = 0.75f
}

/** How much Now Playing's background blurs the artwork. Android 12 and later only; earlier
 *  versions show the dimmed artwork unblurred. */
object BlurRadius {
    val backdrop = 60.dp
    /** Extra blur per line of distance from the lyric being sung, kept subtle so nearby lines
     *  stay readable. */
    val lyricStep = 0.8.dp
    val lyricMaximum = 3.dp
}

object Motion {
    /** Now Playing slides up from the bottom and back down. */
    const val NOW_PLAYING_MILLIS = 350

    /** SwiftUI's `.spring(duration: 0.4, bounce: 0.15)`, the iPhone app's standard motion. */
    fun <T> standard() = spring<T>(dampingRatio = 0.85f, stiffness = 247f)

    /** The standard motion without its bounce, like SwiftUI's `.smooth(duration: 0.4)`, for
     *  sizes, which mustn't overshoot below nothing. */
    fun <T> smooth() = spring<T>(dampingRatio = 1f, stiffness = 247f)

    /** The lyrics glide to a line after a seek on a soft, slightly longer spring, like the iPhone
     *  app's `.spring(duration: 0.6, bounce: 0.12)`. */
    fun <T> lyricFollow() = spring<T>(dampingRatio = 0.88f, stiffness = 110f)

    /** How long a success checkmark stays visible before a sheet closes. */
    val confirmationHold = 600.milliseconds

    /** How long the controls stay over playing lyrics, untouched, before stepping away. */
    val controlsAutoHideDelay = 4.seconds
}

/** How the lyrics move when they advance to the next line. */
object LyricMotion {
    /** Each line follows the one above it this much later, so the lyrics move as a chain. */
    val followDelayPerLine = 50.milliseconds
    /** Lines further below the sung one than this all share the last delay. */
    const val MAX_TRAILING_LINES = 5
    /** A soft spring with a touch of overshoot, like Apple Music's lyrics: the iPhone app's
     *  `Spring(mass: 0.9, stiffness: 90, damping: 15)`, which per unit of mass is this. */
    fun <T> followSpring() = spring<T>(dampingRatio = 0.833f, stiffness = 100f)
    /** Width of the soft edge between sung and unsung text, in characters. */
    const val SWEEP_EDGE_CHARACTERS = 3f
    /** Position reports arrive this often; the sweep eases linearly between them. */
    const val SWEEP_STEP_MILLIS = 250
}

object Layout {
    /** The mini player above the tabs. */
    val miniPlayerHeight = 64.dp
    /** The thin line along the mini player's bottom showing how far the song has played. */
    val miniPlayerProgressHeight = 2.dp
    /** Text and buttons in empty and error states never stretch wider than this. */
    val stateMaxWidth = 320.dp
    const val placeholderSymbolScale = 0.4f
    /** YouTube API Services policy: the embedded player viewport must be at least 200×200. */
    val playerMinimumSide = 200.dp
    const val videoAspectRatio = 16f / 9f
    /** How small the video gets as Up Next scrolls beneath it, so more songs fit. This goes
     *  below `playerMinimumSide`, which YouTube's policy asks for. */
    const val collapsedVideoScale = 0.5f
    /** The off-screen spot the YouTube player waits in while Now Playing is closed. */
    val hiddenPlayerSide = 1.dp
    /** Fits a two-digit chart position so every row's artwork lines up. */
    val chartRankWidth = 28.dp
    /** Now Playing's content never stretches wider than this, so it stays readable on tablets. */
    val nowPlayingMaxWidth = 560.dp
    /** Swiping Now Playing down this far closes it. */
    val nowPlayingDismissDistance = 160.dp
    /** The handle at the top of Now Playing, like the system's grabber. */
    val grabberWidth = 36.dp
    val grabberHeight = 5.dp
    /** Height of the soft fade at the top and bottom of the lyrics. */
    val lyricsEdgeFade = 48.dp
    /** Generous gaps between synced lyric lines, so each stands on its own, as in Apple Music. */
    val lyricsLineSpacing: Dp = Spacing.xxxLarge
    /** Where the line being sung sits, as a fraction of the lyrics' height: near the top, like
     *  Apple Music, so upcoming lines get most of the room. */
    const val lyricsFocus = 0.25f
    /** Upcoming lines fade out over this fraction of the lyrics' height. */
    const val lyricsBottomFadeFraction = 0.3f
    /** The strip along the bottom of the lyrics that brings hidden controls back when tapped. */
    val controlsRevealHeight = 160.dp
    /** Lyrics and Up Next along the bottom of Now Playing, grouped toward the middle like
     *  Apple Music's, rather than pushed to the edges. */
    val nowPlayingAccessorySide = 50.dp
    val nowPlayingAccessorySpacing = 52.dp
    /** Windows at least this wide, like tablets, get larger cards and wider song columns. */
    const val wideLayoutMinWidth = 600
    /** Songs swiped through in columns, like Apple Music's Top Songs: four to a column. */
    const val songColumnRows = 4
    /** How many songs an artist's Top Songs and Discover's Trending show before See All. */
    const val songColumnsShown = 20
    /** Song columns in wide windows, where several fit side by side. */
    val wideSongColumnWidth = 360.dp
    /** How much of the next column or card shows, so a row clearly scrolls. */
    val carouselPeek = 32.dp
    /** Discover's genre tiles: as many across as fit at this width. */
    val genreTileMinWidth = 160.dp
    val genreTileHeight = 96.dp
    val genreSymbolSide = 40.dp
    val shelfLoadingHeight = 120.dp
    val playButtonMinWidth = 132.dp
    val inlineIconSide = 14.dp
    val buttonMaxWidth = 320.dp
    /** Room under a list for the floating "Add to Playlist" button while selecting. */
    val selectionBarSpace = 96.dp
    val inlineProgressSide = 18.dp
    val inlineProgressStroke = 2.dp
    /** Full-bleed Now Playing artwork is as tall as it is wide, but never takes more than this
     *  share of the screen, so the controls stay in view. */
    const val immersiveArtworkMaxHeightFraction = 0.55f
    /** The bottom share of full-bleed artwork that fades into the backdrop. */
    const val immersiveArtworkFadeFraction = 0.35f
    /** Artwork eases back to this size while paused, as in Apple Music. */
    const val pausedArtworkScale = 0.85f
    /** An artist's header is as tall as the page is wide, up to this share of its height. */
    const val artistHeaderMaxHeightFraction = 0.5f
    /** Up Next fades out over this much at an edge with more songs past it. */
    val queueEdgeFade = 32.dp
    val dragHandleSide = 24.dp
    val stepIndicatorDot = 8.dp
    val stepIndicatorActiveWidth = 24.dp
}
