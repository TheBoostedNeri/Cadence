package com.nerijus.cadence.features.player

import android.content.Intent
import android.view.accessibility.AccessibilityManager
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.basicMarquee
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.automirrored.filled.PlaylistAdd
import androidx.compose.material.icons.automirrored.filled.PlaylistPlay
import androidx.compose.material.icons.filled.Album
import androidx.compose.material.icons.filled.FastForward
import androidx.compose.material.icons.filled.FastRewind
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Lyrics
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.outlined.Lyrics
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.lerp
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onPlaced
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.lerp
import androidx.compose.ui.unit.max
import androidx.compose.ui.unit.min
import androidx.core.view.WindowCompat
import com.nerijus.cadence.app.LocalAppContainer
import com.nerijus.cadence.app.LocalRouter
import com.nerijus.cadence.app.findActivity
import com.nerijus.cadence.config.LyricsPolicy
import com.nerijus.cadence.config.PlaybackPolicy
import com.nerijus.cadence.designsystem.ArtworkSize
import com.nerijus.cadence.designsystem.BlurRadius
import com.nerijus.cadence.designsystem.CadenceTheme
import com.nerijus.cadence.designsystem.IconSize
import com.nerijus.cadence.designsystem.Layout
import com.nerijus.cadence.designsystem.Motion
import com.nerijus.cadence.designsystem.Opacity
import com.nerijus.cadence.designsystem.Palette
import com.nerijus.cadence.designsystem.Radius
import com.nerijus.cadence.designsystem.Spacing
import com.nerijus.cadence.designsystem.TouchTarget
import com.nerijus.cadence.designsystem.components.ArtworkImage
import com.nerijus.cadence.designsystem.components.ErrorDialog
import com.nerijus.cadence.designsystem.components.MenuItem
import com.nerijus.cadence.designsystem.components.edgeFade
import com.nerijus.cadence.model.AppError
import com.nerijus.cadence.model.Track
import com.nerijus.cadence.network.TimeFormatting
import com.nerijus.cadence.playback.PlaybackStatus
import com.nerijus.cadence.playback.PlayerController
import com.nerijus.cadence.playback.YouTubePlayerHost
import kotlin.math.roundToInt
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** What takes the artwork's place: the lyrics or Up Next. */
private enum class Panel { Lyrics, Queue }

/**
 * The song playing, over its blurred artwork: YouTube's video (which must show while it plays),
 * or with background play on, the artwork edge to edge, like Apple Music. Then the song with its
 * star and ⋯, the scrubber, the transport controls, the volume, and Lyrics and Up Next. Swipe
 * down, tap the handle or press Back to close it.
 *
 * With the lyrics or Up Next open they take the space above the controls, and the artwork glides
 * into the corner beside the song. Over playing lyrics the controls step away untouched; tapping
 * near the bottom brings them back.
 */
@Composable
fun NowPlayingScreen(player: PlayerController) {
    val track = player.currentTrack ?: return
    val container = LocalAppContainer.current
    val scope = rememberCoroutineScope()
    val dragOffset = remember { Animatable(0f) }
    val dismissDistance = with(LocalDensity.current) { Layout.nowPlayingDismissDistance.toPx() }
    var panel by rememberSaveable { mutableStateOf<Panel?>(null) }
    // Music videos show their video, as the Song and Video switch chooses; songs show artwork.
    val showsVideo = track.showsVideo
    val artworkSlot = remember { ArtworkSlot() }
    val videoCollapse = remember { VideoCollapse() }
    // Up Next opens at its top, under the full-size video.
    LaunchedEffect(panel) { videoCollapse.reset() }
    // Buffering mid-song counts as playing, so a stall doesn't bring the controls back.
    val controls = rememberControlsVisibility(canHide = panel == Panel.Lyrics && player.status.isActive)

    BackHandler(onBack = player::dismissNowPlaying)
    LightSystemBarIcons()

    // Now Playing is dark whatever the system's appearance, like Apple Music's.
    CadenceTheme(darkTheme = true) {
        BoxWithConstraints(
            modifier = Modifier
                .fillMaxSize()
                .offset { IntOffset(0, dragOffset.value.roundToInt()) }
                .background(Palette.playerBackground)
                .draggable(
                    state = rememberDraggableState { delta ->
                        scope.launch { dragOffset.snapTo(maxOf(0f, dragOffset.value + delta)) }
                    },
                    orientation = Orientation.Vertical,
                    onDragStopped = {
                        if (dragOffset.value > dismissDistance) player.dismissNowPlaying() else dragOffset.animateTo(0f)
                    },
                )
                .onPlaced { artworkSlot.screen = it },
        ) {
            Backdrop(track)
            if (!showsVideo) {
                MovingArtwork(
                    track = track,
                    isCompact = panel != null,
                    // As tall as it is wide, but never so tall the controls leave the screen.
                    immersive = DpSize(maxWidth, min(maxWidth, maxHeight * Layout.immersiveArtworkMaxHeightFraction)),
                    slot = artworkSlot,
                )
            }
            Column(
                modifier = Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.systemBars),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Grabber(onClick = player::dismissNowPlaying)
                if (track.hasOtherVersions) VersionSwitch(track, player)
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .widthIn(max = Layout.nowPlayingMaxWidth)
                        .fillMaxWidth()
                        .padding(horizontal = Spacing.xLarge)
                        .padding(bottom = Spacing.large),
                    verticalArrangement = Arrangement.spacedBy(Spacing.xLarge),
                ) {
                    if (showsVideo) PlayerArea(player, collapse = videoCollapse.takeIf { panel == Panel.Queue })
                    // The song sits just above the controls, or the small header and the lyrics or
                    // Up Next take the room above them; they crossfade, like Apple Music's, while
                    // the controls stay exactly where they are.
                    AnimatedContent(
                        targetState = panel,
                        modifier = Modifier
                            .weight(1f)
                            .then(if (showsVideo && panel == Panel.Queue) Modifier.nestedScroll(videoCollapse) else Modifier),
                        transitionSpec = { fadeIn(Motion.standard()) togetherWith fadeOut(Motion.standard()) },
                        label = "panel",
                    ) { shown ->
                        Column(
                            modifier = Modifier.fillMaxSize(),
                            verticalArrangement = if (shown == null) Arrangement.Bottom else Arrangement.spacedBy(Spacing.large),
                        ) {
                            val header = @Composable {
                                TrackHeader(
                                    track = track,
                                    artworkSlot = if (shown != null && !showsVideo) artworkSlot.compactModifier else null,
                                    isShowingLyrics = shown == Panel.Lyrics,
                                    onTap = if (shown != null) ({ panel = null }) else null,
                                )
                            }
                            // Under a video, Up Next scrolls the song away with its list; the
                            // artwork's small spot stays put, so it keeps its header still.
                            val scrollsHeader = shown == Panel.Queue && showsVideo
                            if (!scrollsHeader) header()
                            when (shown) {
                                Panel.Lyrics -> LyricsPanel(track, Modifier.weight(1f))
                                Panel.Queue -> QueuePanel(player, Modifier.weight(1f), header = header.takeIf { scrollsHeader })
                                null -> Unit
                            }
                        }
                    }
                    AnimatedVisibility(
                        visible = !controls.isHidden,
                        // They sink and fade away, and rise back in, like Apple Music's, while the
                        // lyrics grow and shrink with them rather than jumping once they've gone.
                        enter = expandVertically(Motion.smooth(), expandFrom = Alignment.Top, clip = false) +
                            slideInVertically(Motion.smooth()) { it } + fadeIn(Motion.smooth()),
                        exit = shrinkVertically(Motion.smooth(), shrinkTowards = Alignment.Top, clip = false) +
                            slideOutVertically(Motion.smooth()) { it } + fadeOut(Motion.smooth()),
                    ) {
                        PlaybackControls(
                            player = player,
                            panel = panel,
                            onSelectPanel = { panel = if (panel == it) null else it },
                            // Without background play, YouTube may only play while this is open.
                            showsPauseNotice = !container.settings.isBackgroundPlayEnabled && panel == null,
                            modifier = Modifier.trackingTouches { controls.isTouching = it },
                        )
                    }
                }
            }
            if (controls.isHidden) {
                // Tapping near the bottom brings the controls back, like Apple Music.
                Box(
                    Modifier
                        .align(Alignment.BottomCenter)
                        .fillMaxWidth()
                        .height(Layout.controlsRevealHeight)
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            onClickLabel = "Show controls",
                            onClick = controls::reveal,
                        ),
                )
            }
        }
    }
}

/** Shrinks the video as Up Next scrolls beneath it: scrolling the songs up shrinks it first, to
 *  `collapsedVideoScale` of its size, before the list moves, and pulling down at the top of the
 *  list grows it back. */
@Stable
private class VideoCollapse : NestedScrollConnection {
    /** The video's full height, in pixels. */
    var fullHeight by mutableFloatStateOf(0f)
    /** How many pixels it has shrunk by. */
    private var shrink by mutableFloatStateOf(0f)
    private val maxShrink: Float get() = fullHeight * (1 - Layout.collapsedVideoScale)

    val scale: Float get() = if (fullHeight > 0) 1 - shrink / fullHeight else 1f

    fun reset() {
        shrink = 0f
    }

    override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
        if (available.y >= 0) return Offset.Zero
        val before = shrink
        shrink = (shrink - available.y).coerceAtMost(maxShrink)
        return Offset(0f, before - shrink)
    }

    override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
        if (available.y <= 0) return Offset.Zero
        val before = shrink
        shrink = (shrink - available.y).coerceAtLeast(0f)
        return Offset(0f, before - shrink)
    }
}

/** Scales the video from its top edge and gives up the room it no longer needs. It scales rather
 *  than resizing the player, which would make YouTube lay out every frame; the scale is read only
 *  while laying out and drawing, so scrolling never recomposes Now Playing. */
private fun Modifier.collapsing(collapse: VideoCollapse) = layout { measurable, constraints ->
    val placeable = measurable.measure(constraints)
    collapse.fullHeight = placeable.height.toFloat()
    layout(placeable.width, (placeable.height * collapse.scale).roundToInt()) { placeable.place(0, 0) }
}.graphicsLayer {
    scaleX = collapse.scale
    scaleY = collapse.scale
    transformOrigin = TransformOrigin(0.5f, 0f)
}

/** Whether the controls under the lyrics have stepped away. */
@Stable
private class ControlsVisibility {
    var isHidden by mutableStateOf(false)
    var isTouching by mutableStateOf(false)
    /** Bumped when they're brought back, so the countdown starts over. */
    var reveals by mutableIntStateOf(0)

    fun reveal() {
        reveals += 1
        isHidden = false
    }
}

/** The controls step away once they've gone untouched for a few seconds while lyrics play, and
 *  never with TalkBack on, which would lose them. Paused, touched or with the lyrics closed, they
 *  come back. */
@Composable
private fun rememberControlsVisibility(canHide: Boolean): ControlsVisibility {
    val visibility = remember { ControlsVisibility() }
    val context = LocalContext.current
    val isScreenReaderOn = remember(context) {
        context.getSystemService(AccessibilityManager::class.java)?.isTouchExplorationEnabled == true
    }
    val isRunning = canHide && !visibility.isTouching && !isScreenReaderOn
    LaunchedEffect(isRunning, visibility.reveals) {
        if (!isRunning) {
            if (!visibility.isTouching) visibility.isHidden = false
            return@LaunchedEffect
        }
        delay(Motion.controlsAutoHideDelay)
        visibility.isHidden = true
    }
    return visibility
}

/** Reports when a finger is down anywhere on this content, without taking the touch from it. */
private fun Modifier.trackingTouches(onTouchingChange: (Boolean) -> Unit) = pointerInput(Unit) {
    awaitEachGesture {
        awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
        onTouchingChange(true)
        try {
            do {
                val event = awaitPointerEvent(PointerEventPass.Initial)
            } while (event.changes.any { it.pressed })
        } finally {
            onTouchingChange(false)
        }
    }
}

/** The artwork, blurred and dimmed, fills the screen behind everything, like Apple Music. */
@Composable
private fun Backdrop(track: Track) {
    Box(Modifier.fillMaxSize()) {
        ArtworkImage(track.largeArtworkUrl ?: track.artworkUrl, Modifier.fillMaxSize().blur(BlurRadius.backdrop))
        Box(Modifier.fillMaxSize().background(Palette.playerBackground.copy(alpha = Opacity.backdropDim)))
    }
}

/** Where the small artwork goes over the lyrics or Up Next, measured against Now Playing itself,
 *  so swiping the screen down doesn't move it. */
@Stable
private class ArtworkSlot {
    var screen: LayoutCoordinates? = null
    var compact by mutableStateOf<Rect?>(null)

    val compactModifier = Modifier.onGloballyPositioned { coordinates ->
        val screen = screen?.takeIf { it.isAttached } ?: return@onGloballyPositioned
        compact = screen.localBoundingBoxOf(coordinates, clipBounds = false)
    }
}

/**
 * One artwork view, in whichever spot is showing: full width, running up under the status bar
 * and melting into the backdrop, or small beside the song over the lyrics or Up Next. Being the
 * same view, it glides between them, like Apple Music's, instead of one fading and the other
 * popping in.
 *
 * The image keeps its full size and is only scaled, so it isn't decoded again on every frame.
 */
@Composable
private fun MovingArtwork(track: Track, isCompact: Boolean, immersive: DpSize, slot: ArtworkSlot) {
    val density = LocalDensity.current
    val progress by animateFloatAsState(if (isCompact) 1f else 0f, Motion.standard(), label = "artwork")
    // The corners and fade don't bounce past either end.
    val settled = progress.coerceIn(0f, 1f)
    val full = with(density) { Rect(0f, 0f, immersive.width.toPx(), immersive.height.toPx()) }
    val frame = lerp(full, slot.compact ?: full, progress)
    val coverSide = maxOf(full.width, full.height)
    val scale = maxOf(frame.width, frame.height) / coverSide
    Box(
        modifier = Modifier
            .offset { IntOffset(frame.left.roundToInt(), frame.top.roundToInt()) }
            .size(with(density) { DpSize(frame.width.toDp(), frame.height.toDp()) })
            .clip(RoundedCornerShape(lerp(Radius.none, Radius.small, settled)))
            .edgeFade(top = Spacing.none, bottom = immersive.height * Layout.immersiveArtworkFadeFraction * (1 - settled)),
        contentAlignment = Alignment.Center,
    ) {
        ArtworkImage(
            track.largeArtworkUrl ?: track.artworkUrl,
            Modifier
                .requiredSize(with(density) { coverSide.toDp() })
                .graphicsLayer {
                    scaleX = scale
                    scaleY = scale
                },
        )
    }
}

@Composable
private fun Grabber(onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(TouchTarget.minimum)
            .clickable(onClick = onClick)
            .semantics { contentDescription = "Close Now Playing" },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(Layout.grabberWidth, Layout.grabberHeight)
                .clip(RoundedCornerShape(Layout.grabberHeight))
                .background(Palette.onPlayer.copy(alpha = Opacity.scrubberTrack)),
        )
    }
}

/** Song or Video, like the switch at the top of YouTube Music's player: the album audio, which
 *  synced lyrics are timed against, or the music video. */
@Composable
private fun VersionSwitch(track: Track, player: PlayerController) {
    val scope = rememberCoroutineScope()
    // The side being switched to, shown while it's found.
    var requested by remember(track.id) { mutableStateOf<Boolean?>(null) }
    var error by remember { mutableStateOf<AppError?>(null) }
    val showsVideo = requested ?: track.isMusicVideo
    Row(
        modifier = Modifier
            .padding(bottom = Spacing.small)
            .clip(RoundedCornerShape(percent = 50))
            .background(Palette.onPlayer.copy(alpha = Opacity.switchTrack))
            .padding(Spacing.xxSmall)
            .selectableGroup(),
    ) {
        for ((isVideo, title) in listOf(false to "Song", true to "Video")) {
            val isSelected = isVideo == showsVideo
            Text(
                title,
                style = MaterialTheme.typography.labelLarge,
                color = Palette.onPlayer,
                modifier = Modifier
                    .clip(RoundedCornerShape(percent = 50))
                    .background(if (isSelected) Palette.onPlayer.copy(alpha = Opacity.scrubberTrack) else Color.Transparent)
                    .selectable(selected = isSelected, enabled = !player.isSwitchingVersion, role = Role.Tab) {
                        if (isSelected) return@selectable
                        requested = isVideo
                        scope.launch {
                            try {
                                player.switchVersion(toVideo = isVideo)
                            } catch (failure: Exception) {
                                error = AppError.from(failure)
                            } finally {
                                requested = null
                            }
                        }
                    }
                    .padding(horizontal = Spacing.large, vertical = Spacing.small),
            )
        }
    }
    ErrorDialog(error) { error = null }
}

/** YouTube's video, never smaller than the 200×200 YouTube's policy requires, with a spinner
 *  while it loads and what went wrong if it can't play. */
@Composable
private fun PlayerArea(player: PlayerController, collapse: VideoCollapse? = null) {
    BoxWithConstraints(Modifier.fillMaxWidth().then(if (collapse != null) Modifier.collapsing(collapse) else Modifier)) {
        val height: Dp = max(maxWidth / Layout.videoAspectRatio, Layout.playerMinimumSide)
        Box(
            modifier = Modifier.fillMaxWidth().height(height).clip(RoundedCornerShape(Radius.medium)),
            contentAlignment = Alignment.Center,
        ) {
            YouTubePlayerHost(player.webView, Modifier.fillMaxSize())
            when (val status = player.status) {
                is PlaybackStatus.Failed -> PlaybackFailureView(status, player)
                else -> if (status.isWaiting) CircularProgressIndicator(color = Palette.onPlayer)
            }
        }
    }
}

@Composable
private fun PlaybackFailureView(status: PlaybackStatus.Failed, player: PlayerController) {
    Column(
        modifier = Modifier.fillMaxSize().background(Palette.playerBackground).padding(Spacing.large),
        verticalArrangement = Arrangement.spacedBy(Spacing.small, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(status.error.title, style = MaterialTheme.typography.titleMedium, color = Palette.onPlayer)
        Text(
            status.error.message,
            style = MaterialTheme.typography.bodySmall,
            color = Palette.onPlayer.copy(alpha = Opacity.secondaryOnMedia),
            textAlign = TextAlign.Center,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.small)) {
            FilledTonalButton(onClick = player::resume) { Text("Try Again") }
            if (player.hasNext) TextButton(onClick = player::next) { Text("Skip", color = Palette.onPlayer) }
        }
    }
}

/** The song with its star and ⋯. Over the lyrics or Up Next, small artwork joins it when there's
 *  no video above, and tapping it brings the artwork back. `MovingArtwork` draws that artwork
 *  where `artworkSlot` lays out, so it glides there from full size. */
@Composable
private fun TrackHeader(track: Track, artworkSlot: Modifier?, isShowingLyrics: Boolean, onTap: (() -> Unit)?) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.medium),
    ) {
        Row(
            modifier = Modifier
                .weight(1f)
                .then(if (onTap != null) Modifier.clickable(onClickLabel = "Show the artwork", onClick = onTap) else Modifier),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.medium),
        ) {
            if (artworkSlot != null) Spacer(Modifier.size(ArtworkSize.compactHeader).then(artworkSlot))
            Column(Modifier.weight(1f)) {
                Text(track.title, modifier = Modifier.basicMarquee(), style = MaterialTheme.typography.titleLarge, color = Palette.onPlayer, maxLines = 1)
                Text(
                    track.artist,
                    style = MaterialTheme.typography.titleMedium,
                    color = Palette.onPlayer.copy(alpha = Opacity.secondaryOnMedia),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        LikeButton(track)
        MoreMenu(track, isShowingLyrics)
    }
}

private val headerButtonColors
    @Composable get() = IconButtonDefaults.iconButtonColors(
        containerColor = Palette.onPlayer.copy(alpha = Opacity.controlFill),
        contentColor = Palette.onPlayer,
    )

/** Likes the video on the user's YouTube account. Only shows with an account connected. */
@Composable
private fun LikeButton(track: Track) {
    val likes = LocalAppContainer.current.likes
    val scope = rememberCoroutineScope()
    var error by remember { mutableStateOf<AppError?>(null) }
    if (!likes.canLike(track)) return
    LaunchedEffect(track.id) { likes.load(track) }
    val isLiked = likes.isLiked(track)
    IconButton(
        onClick = {
            scope.launch {
                try {
                    likes.toggle(track)
                } catch (failure: Exception) {
                    error = AppError.from(failure)
                }
            }
        },
        colors = headerButtonColors,
        modifier = Modifier.semantics { selected = isLiked },
    ) {
        Icon(if (isLiked) Icons.Filled.Star else Icons.Filled.StarBorder, contentDescription = if (isLiked) "Unlike" else "Like")
    }
    ErrorDialog(error) { error = null }
}

/** Add to Playlist, the album and artist, lyrics timing while they show, and sharing. */
@Composable
private fun MoreMenu(track: Track, isShowingLyrics: Boolean) {
    val container = LocalAppContainer.current
    val lyrics = container.lyrics
    val router = LocalRouter.current
    val player = container.player
    val context = LocalContext.current
    val uriHandler = LocalUriHandler.current
    var isExpanded by remember { mutableStateOf(false) }
    fun pick(action: () -> Unit) {
        isExpanded = false
        action()
    }
    Box {
        IconButton(onClick = { isExpanded = true }, colors = headerButtonColors) {
            Icon(Icons.Filled.MoreHoriz, contentDescription = "More")
        }
        DropdownMenu(expanded = isExpanded, onDismissRequest = { isExpanded = false }) {
            MenuItem("Add to Playlist…", Icons.AutoMirrored.Filled.PlaylistAdd) { pick { router.addToPlaylist(listOf(track)) } }
            // These open in the tab behind; Now Playing closes to show them.
            MenuItem("Go to Album", Icons.Filled.Album) { pick { player.dismissNowPlaying(); router.showAlbum(track) } }
            MenuItem("Go to Artist", Icons.Filled.Mic) { pick { player.dismissNowPlaying(); router.showArtist(track) } }
            // Music videos show their lyrics without timing, so there's none to adjust.
            if (isShowingLyrics && !track.isMusicVideo) {
                HorizontalDivider()
                Text(
                    "Lyrics Timing",
                    modifier = Modifier.padding(horizontal = Spacing.large, vertical = Spacing.small),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                MenuItem("Show Lyrics Earlier", Icons.Filled.FastRewind) { lyrics.adjustOffset(-LyricsPolicy.OFFSET_STEP, track) }
                MenuItem("Show Lyrics Later", Icons.Filled.FastForward) { lyrics.adjustOffset(LyricsPolicy.OFFSET_STEP, track) }
                if (lyrics.offset(track) != 0.0) {
                    MenuItem("Reset Timing", Icons.Filled.Restore) { pick { lyrics.setOffset(0.0, track) } }
                }
                HorizontalDivider()
            }
            MenuItem("Share", Icons.Filled.Share) {
                pick {
                    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, track.externalUrl)
                    context.startActivity(Intent.createChooser(send, null))
                }
            }
            MenuItem("Open in YouTube", Icons.AutoMirrored.Filled.OpenInNew) { pick { uriHandler.openUri(track.externalUrl) } }
        }
    }
}

/** The same under the video or artwork and under the lyrics or Up Next, so switching never moves
 *  them. */
@Composable
private fun PlaybackControls(
    player: PlayerController,
    panel: Panel?,
    onSelectPanel: (Panel) -> Unit,
    showsPauseNotice: Boolean,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.xLarge)) {
        Scrubber(player)
        TransportControls(player)
        VolumeSlider()
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(Layout.nowPlayingAccessorySpacing, Alignment.CenterHorizontally),
        ) {
            PanelButton("Lyrics", if (panel == Panel.Lyrics) Icons.Filled.Lyrics else Icons.Outlined.Lyrics, panel == Panel.Lyrics) {
                onSelectPanel(Panel.Lyrics)
            }
            PanelButton("Up Next", Icons.AutoMirrored.Filled.PlaylistPlay, panel == Panel.Queue) { onSelectPanel(Panel.Queue) }
        }
        if (showsPauseNotice) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.small)) {
                Icon(
                    Icons.Filled.Info,
                    contentDescription = null,
                    modifier = Modifier.size(Layout.inlineIconSide),
                    tint = Palette.onPlayer.copy(alpha = Opacity.secondaryOnMedia),
                )
                Text(
                    "Playback pauses when you close the player, as YouTube's Terms of Service require.",
                    style = MaterialTheme.typography.bodySmall,
                    color = Palette.onPlayer.copy(alpha = Opacity.secondaryOnMedia),
                )
            }
        }
    }
}

/** Filled, in a soft circle, while its panel shows, like Apple Music's. */
@Composable
private fun PanelButton(title: String, icon: ImageVector, isOpen: Boolean, onClick: () -> Unit) {
    IconButton(
        onClick = onClick,
        modifier = Modifier.size(Layout.nowPlayingAccessorySide).semantics { selected = isOpen },
        colors = IconButtonDefaults.iconButtonColors(
            containerColor = if (isOpen) Palette.onPlayer.copy(alpha = Opacity.controlFill) else Color.Transparent,
            contentColor = if (isOpen) Palette.onPlayer else Palette.onPlayer.copy(alpha = Opacity.secondaryOnMedia),
        ),
    ) {
        Icon(icon, contentDescription = title)
    }
}

/** The song's position, draggable; it seeks when let go, so YouTube isn't asked to seek on every
 *  step of the drag. */
@Composable
private fun Scrubber(player: PlayerController) {
    var draggedTo by remember { mutableStateOf<Float?>(null) }
    val length = maxOf(player.duration, PlaybackPolicy.MINIMUM_SLIDER_RANGE).toFloat()
    val position = draggedTo ?: player.currentTime.toFloat().coerceIn(0f, length)
    val secondaryText = Palette.onPlayer.copy(alpha = Opacity.secondaryOnMedia)

    Column(Modifier.fillMaxWidth()) {
        Slider(
            value = position,
            onValueChange = { draggedTo = it },
            onValueChangeFinished = {
                draggedTo?.let { player.seek(it.toDouble()) }
                draggedTo = null
            },
            valueRange = 0f..length,
            enabled = player.duration > 0,
            colors = SliderDefaults.colors(
                thumbColor = Palette.onPlayer,
                activeTrackColor = Palette.onPlayer,
                inactiveTrackColor = Palette.onPlayer.copy(alpha = Opacity.scrubberTrack),
            ),
        )
        Row(Modifier.fillMaxWidth()) {
            Text(TimeFormatting.string(position.toDouble()), style = MaterialTheme.typography.labelMedium, color = secondaryText)
            Spacer(Modifier.weight(1f))
            Text("-" + TimeFormatting.string(player.duration - position), style = MaterialTheme.typography.labelMedium, color = secondaryText)
        }
    }
}

@Composable
private fun TransportControls(player: PlayerController) {
    val isActive = player.status.isActive
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceEvenly,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TransportButton(Icons.Filled.SkipPrevious, "Previous", TouchTarget.secondary, IconSize.transportSecondary, enabled = player.hasPrevious, onClick = player::previous)
        TransportButton(
            if (isActive) Icons.Filled.Pause else Icons.Filled.PlayArrow,
            if (isActive) "Pause" else "Play",
            TouchTarget.primary,
            IconSize.transportPrimary,
            onClick = player::togglePlayPause,
        )
        TransportButton(Icons.Filled.SkipNext, "Next", TouchTarget.secondary, IconSize.transportSecondary, enabled = player.hasNext, onClick = player::next)
    }
}

@Composable
private fun TransportButton(
    icon: ImageVector,
    label: String,
    side: Dp,
    iconSide: Dp,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    IconButton(
        onClick = onClick,
        modifier = modifier.size(side),
        enabled = enabled,
        colors = IconButtonDefaults.iconButtonColors(
            contentColor = Palette.onPlayer,
            disabledContentColor = Palette.onPlayer.copy(alpha = Opacity.inactive),
        ),
    ) {
        Icon(icon, contentDescription = label, modifier = Modifier.size(iconSide))
    }
}

/** Now Playing is always dark, so the status and navigation bar icons turn light while it shows. */
@Composable
private fun LightSystemBarIcons() {
    val view = LocalView.current
    DisposableEffect(view) {
        val window = view.context.findActivity()?.window ?: return@DisposableEffect onDispose {}
        val controller = WindowCompat.getInsetsController(window, view)
        val wereStatusBarIconsDark = controller.isAppearanceLightStatusBars
        val wereNavigationBarIconsDark = controller.isAppearanceLightNavigationBars
        controller.isAppearanceLightStatusBars = false
        controller.isAppearanceLightNavigationBars = false
        onDispose {
            controller.isAppearanceLightStatusBars = wereStatusBarIconsDark
            controller.isAppearanceLightNavigationBars = wereNavigationBarIconsDark
        }
    }
}
