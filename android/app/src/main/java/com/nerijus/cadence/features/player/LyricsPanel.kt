package com.nerijus.cadence.features.player

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.draw.blur
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onPlaced
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.max
import androidx.compose.ui.unit.min
import com.nerijus.cadence.app.LocalAppContainer
import com.nerijus.cadence.app.LocalPlayer
import com.nerijus.cadence.config.LyricsPolicy
import com.nerijus.cadence.designsystem.BlurRadius
import com.nerijus.cadence.designsystem.Layout
import com.nerijus.cadence.designsystem.LyricMotion
import com.nerijus.cadence.designsystem.LyricType
import com.nerijus.cadence.designsystem.Motion
import com.nerijus.cadence.designsystem.Opacity
import com.nerijus.cadence.designsystem.Palette
import com.nerijus.cadence.designsystem.Spacing
import com.nerijus.cadence.designsystem.components.EmptyState
import com.nerijus.cadence.designsystem.components.ErrorState
import com.nerijus.cadence.designsystem.components.edgeFade
import com.nerijus.cadence.lyrics.LyricLine
import com.nerijus.cadence.lyrics.Lyrics
import com.nerijus.cadence.model.AppError
import com.nerijus.cadence.model.LoadState
import com.nerijus.cadence.model.Track
import com.nerijus.cadence.playback.PlaybackStatus
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Lyrics for the current song, fetched only while they're open. */
@Composable
fun LyricsPanel(track: Track, modifier: Modifier = Modifier) {
    val lyricsService = LocalAppContainer.current.lyrics
    val player = LocalPlayer.current
    // The length of what's actually playing, once the player reports it, to the second.
    val playingDuration = if (player.duration > 0) player.duration.roundToInt() else track.duration?.roundToInt()
    var lyrics by remember { mutableStateOf<LoadState<Lyrics?>>(LoadState.Idle) }
    var loadedTrackId by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableIntStateOf(0) }

    LaunchedEffect(track.id, playingDuration, attempt) {
        // A new song starts from scratch; a corrected length quietly re-picks the lyrics.
        if (loadedTrackId != track.id) {
            lyrics = LoadState.Idle
            loadedTrackId = track.id
        }
        if (lyrics !is LoadState.Loaded) lyrics = LoadState.Loading
        lyrics = try {
            LoadState.Loaded(lyricsService.lyrics(track, playingDuration?.toDouble()))
        } catch (error: Exception) {
            LoadState.Failed(AppError.from(error))
        }
    }

    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        when (val state = lyrics) {
            LoadState.Idle, LoadState.Loading -> Column(
                verticalArrangement = Arrangement.spacedBy(Spacing.medium),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                CircularProgressIndicator(color = Palette.onPlayer)
                Text(
                    "Finding lyrics…",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            is LoadState.Failed -> ErrorState(state.error, onRetry = { attempt += 1 })
            is LoadState.Loaded -> when (val found = state.value) {
                null -> EmptyState(
                    title = "No Lyrics Found",
                    icon = Icons.Outlined.ChatBubbleOutline,
                    message = "LRCLIB doesn't have lyrics for this song yet.",
                )
                Lyrics.Instrumental -> EmptyState(
                    title = "Instrumental",
                    icon = Icons.Filled.MusicNote,
                    message = "This track has no lyrics.",
                )
                is Lyrics.Plain -> StillLyrics(found.text, note = "These lyrics aren't time-synced.")
                // Music videos' intros and skits throw the timing off, so the lyrics hold still.
                is Lyrics.Synced -> if (track.isMusicVideo) {
                    StillLyrics(
                        found.lines.joinToString("\n") { it.text },
                        note = "Lyrics hold still during music videos. Switch to Song to follow along.",
                    )
                } else {
                    SyncedLyrics(
                        lines = found.lines,
                        currentTime = player.currentTime,
                        isPlaying = player.status == PlaybackStatus.Playing,
                        offset = lyricsService.offset(track),
                        isWordSweepEnabled = lyricsService.isWordSweepEnabled,
                        onSeek = { time -> player.seek(maxOf(0.0, time)) },
                        onSyncLine = { line -> lyricsService.setOffset(player.currentTime - line.time, track) },
                    )
                }
            }
        }
    }
}

/** Lyrics as one block of text to scroll through, with no line following the song. */
@Composable
private fun StillLyrics(text: String, note: String) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .edgeFade(top = Layout.lyricsEdgeFade, bottom = Layout.lyricsEdgeFade)
            .verticalScroll(rememberScrollState())
            .padding(vertical = Layout.lyricsEdgeFade),
        verticalArrangement = Arrangement.spacedBy(Spacing.large),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xSmall), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Outlined.Info, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(
                note,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Text(text, style = LyricType.plain, color = Palette.onPlayer)
    }
}

/** Where each line was laid out, in pixels. A plain class, so updating it as the lyrics lay
 *  out never redraws them. */
private class LyricMetrics {
    val tops = mutableMapOf<Int, Int>()
    val heights = mutableMapOf<Int, Int>()

    /** The scroll position that brings `lineId` to the focus position, or null until it's laid out. */
    fun scrollTarget(lineId: Int, viewportHeight: Int): Int? {
        val top = tops[lineId] ?: return null
        val height = heights[lineId] ?: return null
        return (top + height * Layout.lyricsFocus - viewportHeight * Layout.lyricsFocus).roundToInt()
    }
}

/**
 * Apple Music–style lyrics: the line being sung is bright, sharp and kept near the top; other
 * lines dim and blur progressively with distance from it. Everything sharpens while paused or
 * scrolling, and auto-scrolling picks up again at the next line.
 *
 * When they advance, the scroll jumps straight to the new line and every line starts back where
 * it was, then glides up on its own spring: the new line and the ones already sung together, then
 * each line below a moment after the one above it. No line ever moves down.
 */
@Composable
private fun SyncedLyrics(
    lines: List<LyricLine>,
    currentTime: Double,
    /** Lines only blur while the song plays; paused lyrics are all sharp and easy to read. */
    isPlaying: Boolean,
    /** Shifts every line; positive values show lyrics later (for videos with intros). */
    offset: Double,
    isWordSweepEnabled: Boolean,
    onSeek: (Double) -> Unit,
    onSyncLine: (LyricLine) -> Unit,
) {
    val scrollState = rememberScrollState()
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    val metrics = remember(lines) { LyricMetrics() }
    val follows = remember(lines) { lines.associate { it.id to Animatable(0f) } }
    val followJobs = remember(lines) { mutableMapOf<Int, Job>() }
    var viewportHeight by remember { mutableIntStateOf(0) }
    var isAutoScrolling by remember { mutableStateOf(false) }
    val isDragged by scrollState.interactionSource.collectIsDraggedAsState()
    // Flings after a drag count as the user's; the app's own scrolls don't.
    val isUserScrolling = isDragged || (scrollState.isScrollInProgress && !isAutoScrolling)

    val viewport = with(density) { viewportHeight.toDp() }
    val bottomFade = max(Layout.lyricsEdgeFade, viewport * Layout.lyricsBottomFadeFraction)
    // Space above the first line and below the last, so even the opening and closing lines can
    // glide to the focus position like the rest instead of the list sitting still.
    val topRunway = max(Layout.lyricsEdgeFade, viewport * Layout.lyricsFocus)
    val bottomRunway = max(bottomFade, viewport * (1 - Layout.lyricsFocus))

    // Advances slightly early so the glide lands as the line is sung, making up for the
    // player's position updates arriving in steps and a little late.
    val activeLineId = lines.lastOrNull { it.time + offset <= currentTime + LyricsPolicy.HIGHLIGHT_LEAD }?.id

    suspend fun jumpTo(lineId: Int) {
        val target = metrics.scrollTarget(lineId, viewportHeight) ?: return
        isAutoScrolling = true
        try {
            scrollState.scrollTo(target)
        } finally {
            isAutoScrolling = false
        }
    }

    LaunchedEffect(activeLineId) {
        val lineId = activeLineId ?: return@LaunchedEffect
        if (isUserScrolling) return@LaunchedEffect
        val target = metrics.scrollTarget(lineId, viewportHeight) ?: return@LaunchedEffect
        val distance = target - scrollState.value
        // Line-by-line advances move as a chain; seeks and long jumps simply glide there.
        if (distance <= 0 || distance >= viewportHeight) {
            isAutoScrolling = true
            try {
                scrollState.animateScrollTo(target, Motion.lyricFollow())
            } finally {
                isAutoScrolling = false
            }
            return@LaunchedEffect
        }
        for (line in lines) {
            val follow = follows.getValue(line.id)
            // A quick next advance carries on from where the line still is.
            val start = follow.value + distance
            val order = (line.id - lineId).coerceIn(0, LyricMotion.MAX_TRAILING_LINES)
            followJobs[line.id]?.cancel()
            followJobs[line.id] = scope.launch {
                follow.snapTo(start)
                delay(LyricMotion.followDelayPerLine * order)
                follow.animateTo(0f, LyricMotion.followSpring())
            }
        }
        jumpTo(lineId)
    }

    // On opening, and when the lyrics' height changes (the runway changes with it), keep the sung
    // line in the focus position. The second frame waits out a resize still under way, like the
    // controls stepping away, which carries the lines along with the runway by itself; scrolling on
    // every step of it would make them shimmer.
    LaunchedEffect(viewportHeight) {
        withFrameNanos {}
        withFrameNanos {}
        val lineId = activeLineId ?: return@LaunchedEffect
        if (!isUserScrolling) jumpTo(lineId)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .onSizeChanged { viewportHeight = it.height }
            // Upcoming lines fade out gently toward the bottom, as in Apple Music.
            .edgeFade(top = Layout.lyricsEdgeFade, bottom = bottomFade)
            .verticalScroll(scrollState),
        verticalArrangement = Arrangement.spacedBy(Layout.lyricsLineSpacing),
    ) {
        // Spacers rather than padding, so line positions include the runway.
        Spacer(Modifier.height(topRunway - Layout.lyricsLineSpacing))
        for (line in lines) {
            val isActive = line.id == activeLineId
            val distance = abs(line.id - (activeLineId ?: 0))
            LyricLineView(
                line = line,
                isActive = isActive,
                blur = if (isPlaying && !isUserScrolling) min(BlurRadius.lyricStep * distance, BlurRadius.lyricMaximum) else 0.dp,
                sweep = sweepProgress(line, activeLineId, currentTime, offset, isWordSweepEnabled),
                isWordSweepEnabled = isWordSweepEnabled,
                onSeek = { onSeek(line.time + offset) },
                onSync = { onSyncLine(line) },
                modifier = Modifier
                    .onPlaced { coordinates ->
                        metrics.tops[line.id] = coordinates.positionInParent().y.roundToInt()
                        metrics.heights[line.id] = coordinates.size.height
                    }
                    .graphicsLayer { translationY = follows.getValue(line.id).value },
            )
        }
        Spacer(Modifier.height(bottomRunway - Layout.lyricsLineSpacing))
    }
}

/** How far the sweep has moved through `line`, from 0 to 1. Sung lines stay at 1 and simply dim,
 *  so finishing a line never plays the sweep backwards. With word-by-word off every line stays
 *  at 1, so the current line just fades up as a whole. */
private fun sweepProgress(
    line: LyricLine,
    activeLineId: Int?,
    currentTime: Double,
    offset: Double,
    isWordSweepEnabled: Boolean,
): Float {
    if (!isWordSweepEnabled) return 1f
    if (activeLineId == null || line.id > activeLineId) return 0f
    if (line.id != activeLineId || line.text.isEmpty()) return 1f
    val elapsed = currentTime + LyricsPolicy.HIGHLIGHT_LEAD - (line.time + offset)
    return (elapsed / line.sweepDuration).toFloat().coerceIn(0f, 1f)
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun LyricLineView(
    line: LyricLine,
    isActive: Boolean,
    blur: Dp,
    sweep: Float,
    isWordSweepEnabled: Boolean,
    onSeek: () -> Unit,
    onSync: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var isMenuShown by remember { mutableStateOf(false) }
    val animatedBlur by animateDpAsState(blur, Motion.standard(), label = "blur")
    val sungOpacity by animateFloatAsState(
        if (isActive) Opacity.opaque else Opacity.inactiveLyric,
        Motion.standard(),
        label = "sung",
    )
    val unsungOpacity by animateFloatAsState(
        if (isActive && isWordSweepEnabled) Opacity.unsungLyric else Opacity.inactiveLyric,
        Motion.standard(),
        label = "unsung",
    )
    // Position updates arrive in steps; easing linearly between them keeps the sweep moving.
    val animatedSweep by animateFloatAsState(
        sweep,
        tween(LyricMotion.SWEEP_STEP_MILLIS, easing = LinearEasing),
        label = "sweep",
    )
    val text = line.text.ifEmpty { "♪" }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .combinedClickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClickLabel = "Play from this line",
                onLongClick = { isMenuShown = true },
                onClick = onSeek,
            )
            .semantics { selected = isActive },
    ) {
        val content = Modifier.blur(animatedBlur, BlurredEdgeTreatment.Unbounded)
        if (isWordSweepEnabled) {
            Text(sweptText(text, animatedSweep, sungOpacity, unsungOpacity), content, style = LyricType.synced)
        } else {
            Text(text, content, style = LyricType.synced, color = Palette.onPlayer.copy(alpha = sungOpacity))
        }
        DropdownMenu(expanded = isMenuShown, onDismissRequest = { isMenuShown = false }) {
            DropdownMenuItem(
                text = { Text("Sync This Line to Now") },
                leadingIcon = { Icon(Icons.Outlined.Timer, contentDescription = null) },
                onClick = {
                    isMenuShown = false
                    onSync()
                },
            )
        }
    }
}

/** Lights a line up character by character in reading order, following wrapped lines, with a
 *  soft edge between sung and unsung text. Longer words have more characters, so they take longer. */
private fun sweptText(text: String, progress: Float, sungOpacity: Float, unsungOpacity: Float): AnnotatedString {
    val count = maxOf(text.codePointCount(0, text.length), 1).toFloat()
    val edge = LyricMotion.SWEEP_EDGE_CHARACTERS / count
    return buildAnnotatedString {
        var index = 0
        var position = 0
        while (index < text.length) {
            val next = text.offsetByCodePoints(index, 1)
            // 0 before the sweep reaches this character, 1 once it has fully passed.
            val lit = ((progress * (1 + edge) - position / count) / edge).coerceIn(0f, 1f)
            val opacity = unsungOpacity + (sungOpacity - unsungOpacity) * lit
            withStyle(SpanStyle(color = Palette.onPlayer.copy(alpha = opacity))) {
                append(text, index, next)
            }
            index = next
            position += 1
        }
    }
}
