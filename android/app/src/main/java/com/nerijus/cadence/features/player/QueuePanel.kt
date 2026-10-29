package com.nerijus.cadence.features.player

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.PlaylistPlay
import androidx.compose.material.icons.filled.AllInclusive
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.RemoveCircleOutline
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.RepeatOne
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.zIndex
import com.nerijus.cadence.designsystem.ArtworkSize
import com.nerijus.cadence.designsystem.Layout
import com.nerijus.cadence.designsystem.Opacity
import com.nerijus.cadence.designsystem.Palette
import com.nerijus.cadence.designsystem.Radius
import com.nerijus.cadence.designsystem.Spacing
import com.nerijus.cadence.designsystem.components.ArtworkImage
import com.nerijus.cadence.designsystem.components.EmptyState
import com.nerijus.cadence.designsystem.components.MenuItem
import com.nerijus.cadence.designsystem.components.edgeFade
import com.nerijus.cadence.model.QueueItem
import com.nerijus.cadence.playback.PlayerController
import com.nerijus.cadence.playback.RepeatMode

/**
 * Up Next like Apple Music's queue: Shuffle, Repeat and Autoplay, then the songs with handles for
 * dragging them into a new order. Autoplay's songs follow below a divider and keep their order.
 * Long-press a song, or use its ⋯, to play it next or remove it.
 */
@Composable
fun QueuePanel(player: PlayerController, modifier: Modifier = Modifier, header: (@Composable () -> Unit)? = null) {
    val listState = rememberLazyListState()
    val upcoming = player.upcoming
    val autoplayUpcoming = player.autoplayUpcoming
    val showsAutoplaySection = player.isAutoplayEnabled && (autoplayUpcoming.isNotEmpty() || player.isFindingAutoplayTracks)
    val currentUpcoming by rememberUpdatedState(upcoming)
    var draggedKey by remember { mutableStateOf<String?>(null) }
    var dragOffset by remember { mutableFloatStateOf(0f) }

    /** Moves the dragged song past a neighbor once it's dragged over the neighbor's middle. */
    fun followDrag(key: String, delta: Float) {
        dragOffset += delta
        val position = currentUpcoming.indexOfFirst { it.key == key }.takeIf { it >= 0 } ?: return
        val visible = listState.layoutInfo.visibleItemsInfo
        val dragged = visible.firstOrNull { it.key == key } ?: return
        val center = dragged.offset + dragOffset + dragged.size / 2
        val neighborPosition = if (dragOffset > 0) position + 1 else position - 1
        val neighbor = currentUpcoming.getOrNull(neighborPosition) ?: return
        val neighborInfo = visible.firstOrNull { it.key == neighbor.key } ?: return
        val neighborMiddle = neighborInfo.offset + neighborInfo.size / 2f
        val hasCrossed = if (dragOffset > 0) center > neighborMiddle else center < neighborMiddle
        if (!hasCrossed) return
        player.moveUpNext(position, neighborPosition)
        // The row now sits where its neighbor was, so the finger's offset is measured from there.
        dragOffset += if (dragOffset > 0) -neighborInfo.size.toFloat() else neighborInfo.size.toFloat()
    }

    LazyColumn(
        state = listState,
        modifier = modifier.edgeFade(top = Layout.queueEdgeFade, bottom = Layout.queueEdgeFade),
        contentPadding = PaddingValues(vertical = Layout.queueEdgeFade),
    ) {
        // The song scrolls away with the list, leaving more room for what's next.
        if (header != null) {
            item(key = "song") { Box(Modifier.padding(bottom = Spacing.large)) { header() } }
        }
        item(key = "modes") { QueueModeButtons(player) }
        item(key = "header") {
            Row(Modifier.fillMaxWidth().padding(top = Spacing.large), verticalAlignment = Alignment.CenterVertically) {
                Text("Continue Playing", style = MaterialTheme.typography.titleMedium, color = Palette.onPlayer, modifier = Modifier.weight(1f))
                if (upcoming.isNotEmpty()) {
                    TextButton(onClick = player::clearUpNext) { Text("Clear", color = Palette.onPlayer) }
                }
            }
        }
        if (upcoming.isEmpty() && !showsAutoplaySection) {
            item(key = "empty") {
                EmptyState(
                    title = "Nothing Up Next",
                    icon = Icons.AutoMirrored.Filled.PlaylistPlay,
                    message = "Songs queued after this one appear here.",
                )
            }
        } else if (upcoming.isEmpty()) {
            item(key = "hint") {
                Text(
                    "Songs you queue play before Autoplay's.",
                    modifier = Modifier.padding(vertical = Spacing.small),
                    style = MaterialTheme.typography.bodySmall,
                    color = Palette.onPlayer.copy(alpha = Opacity.secondaryOnMedia),
                )
            }
        }
        items(upcoming, key = { it.key }) { item ->
            val isDragged = item.key == draggedKey
            QueueRow(
                item = item,
                player = player,
                modifier = if (isDragged) {
                    Modifier
                        .zIndex(1f)
                        .graphicsLayer { translationY = dragOffset }
                        .background(Palette.onPlayer.copy(alpha = Opacity.controlFill), RoundedCornerShape(Radius.medium))
                } else {
                    Modifier.animateItem()
                },
                handle = Modifier.pointerInput(item.key) {
                    detectVerticalDragGestures(
                        onDragStart = {
                            draggedKey = item.key
                            dragOffset = 0f
                        },
                        onDragEnd = { draggedKey = null },
                        onDragCancel = { draggedKey = null },
                        onVerticalDrag = { change, amount ->
                            change.consume()
                            followDrag(item.key, amount)
                        },
                    )
                },
            )
        }
        if (showsAutoplaySection) {
            item(key = "autoplay") { AutoplayHeader(player.isFindingAutoplayTracks && autoplayUpcoming.isEmpty()) }
            items(autoplayUpcoming, key = { it.key }) { item ->
                QueueRow(item, player, Modifier.animateItem(), handle = null)
            }
        }
    }
}

/** Shuffle, Repeat and Autoplay, filled while on. */
@Composable
private fun QueueModeButtons(player: PlayerController) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Spacing.small)) {
        QueueModeButton("Shuffle", Icons.Filled.Shuffle, player.isShuffled, Modifier.weight(1f), player::toggleShuffle)
        QueueModeButton(
            when (player.repeatMode) {
                RepeatMode.Off -> "Repeat"
                RepeatMode.All -> "Repeat All"
                RepeatMode.One -> "Repeat One"
            },
            if (player.repeatMode == RepeatMode.One) Icons.Filled.RepeatOne else Icons.Filled.Repeat,
            player.repeatMode != RepeatMode.Off,
            Modifier.weight(1f),
            player::cycleRepeatMode,
        )
        QueueModeButton("Autoplay", Icons.Filled.AllInclusive, player.isAutoplayEnabled, Modifier.weight(1f), player::toggleAutoplay)
    }
}

@Composable
private fun QueueModeButton(title: String, icon: ImageVector, isOn: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val content = if (isOn) Palette.playerBackground else Palette.onPlayer
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(Radius.large))
            .background(if (isOn) Palette.onPlayer else Palette.onPlayer.copy(alpha = Opacity.controlFill))
            .clickable(onClick = onClick)
            .padding(vertical = Spacing.medium)
            .semantics { selected = isOn },
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = content)
        Text(" $title", style = MaterialTheme.typography.labelLarge, color = content, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** A hairline, then the ∞ and what Autoplay is playing, like Apple Music's. */
@Composable
private fun AutoplayHeader(isFinding: Boolean) {
    Column(Modifier.padding(vertical = Spacing.medium), verticalArrangement = Arrangement.spacedBy(Spacing.large)) {
        HorizontalDivider(color = Palette.onPlayer.copy(alpha = Opacity.scrubberTrack))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.medium)) {
            Box(
                Modifier.size(ArtworkSize.row).clip(CircleShape).background(Palette.onPlayer.copy(alpha = Opacity.controlFill)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.AllInclusive, contentDescription = null, tint = Palette.onPlayer)
            }
            Column {
                Text("Autoplay", style = MaterialTheme.typography.titleMedium, color = Palette.onPlayer)
                Text(
                    if (isFinding) "Finding more music…" else "Similar music",
                    style = MaterialTheme.typography.bodySmall,
                    color = Palette.onPlayer.copy(alpha = Opacity.secondaryOnMedia),
                )
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun QueueRow(item: QueueItem, player: PlayerController, modifier: Modifier, handle: Modifier?) {
    var isMenuShown by remember { mutableStateOf(false) }
    Row(
        modifier = modifier
            .fillMaxWidth()
            .combinedClickable(onClick = { player.skipTo(item.index) }, onLongClick = { isMenuShown = true })
            .padding(vertical = Spacing.small),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.medium),
    ) {
        ArtworkImage(item.track.artworkUrl, Modifier.size(ArtworkSize.row), cornerRadius = Radius.small)
        Column(Modifier.weight(1f)) {
            Text(item.track.title, style = MaterialTheme.typography.bodyLarge, color = Palette.onPlayer, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                item.track.artist,
                style = MaterialTheme.typography.bodyMedium,
                color = Palette.onPlayer.copy(alpha = Opacity.secondaryOnMedia),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Box {
            IconButton(onClick = { isMenuShown = true }) {
                Icon(Icons.Filled.MoreVert, contentDescription = "More for ${item.track.title}", tint = Palette.onPlayer)
            }
            DropdownMenu(expanded = isMenuShown, onDismissRequest = { isMenuShown = false }) {
                MenuItem("Play Next", Icons.AutoMirrored.Filled.PlaylistPlay) {
                    isMenuShown = false
                    player.playNext(queuedAt = item.index)
                }
                MenuItem("Remove from Up Next", Icons.Filled.RemoveCircleOutline, isDestructive = true) {
                    isMenuShown = false
                    player.removeQueued(item.index)
                }
            }
        }
        if (handle != null) {
            Icon(
                Icons.Filled.DragHandle,
                contentDescription = null,
                tint = Palette.onPlayer.copy(alpha = Opacity.secondaryOnMedia),
                modifier = handle.semantics { contentDescription = "Reorder" },
            )
        } else {
            // Autoplay's songs keep their order, so they have no handle; this keeps them aligned.
            Spacer(Modifier.size(Layout.dragHandleSide))
        }
    }
}
