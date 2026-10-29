package com.nerijus.cadence.designsystem.components

import android.content.Intent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.PlaylistAdd
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.Album
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.automirrored.filled.PlaylistPlay
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nerijus.cadence.app.LocalPlayer
import com.nerijus.cadence.app.LocalRouter
import com.nerijus.cadence.designsystem.ArtworkSize
import com.nerijus.cadence.designsystem.Layout
import com.nerijus.cadence.designsystem.Radius
import com.nerijus.cadence.designsystem.Spacing
import com.nerijus.cadence.model.AppError
import com.nerijus.cadence.model.Playlist
import com.nerijus.cadence.model.PlaylistPrivacy
import com.nerijus.cadence.model.Track
import com.nerijus.cadence.model.songCount
import com.nerijus.cadence.network.TimeFormatting

/** A section's title, an optional line under it, and an optional action on the right. */
@Composable
fun SectionHeader(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    actionTitle: String? = null,
    onAction: (() -> Unit)? = null,
) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, modifier = Modifier.semantics { heading() }, style = MaterialTheme.typography.titleLarge)
            subtitle?.let {
                Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (actionTitle != null && onAction != null) {
            TextButton(onClick = onAction) { Text(actionTitle) }
        }
    }
}

/** What a song's menu can remove it from, such as a playlist or Recently Played. */
class TrackRemoval(val title: String, val action: () -> Unit)

/** The actions for a song, shared by its ⋯ button and its long-press menu. */
@Composable
fun TrackMenu(
    track: Track,
    expanded: Boolean,
    onDismiss: () -> Unit,
    showsAlbum: Boolean = true,
    showsArtist: Boolean = true,
    removal: TrackRemoval? = null,
) {
    val player = LocalPlayer.current
    val router = LocalRouter.current
    val context = LocalContext.current
    val uriHandler = LocalUriHandler.current
    fun closeNowPlaying() {
        if (player.isNowPlayingPresented) player.dismissNowPlaying()
    }
    fun pick(action: () -> Unit) {
        onDismiss()
        action()
    }
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
        MenuItem("Play Next", Icons.AutoMirrored.Filled.PlaylistPlay) { pick { player.playNext(track) } }
        MenuItem("Play Last", Icons.AutoMirrored.Filled.QueueMusic) { pick { player.playLast(track) } }
        MenuItem("Add to Playlist…", Icons.AutoMirrored.Filled.PlaylistAdd) { pick { router.addToPlaylist(listOf(track)) } }
        // These open in the tab behind; Now Playing closes to show them.
        if (showsAlbum) MenuItem("Go to Album", Icons.Filled.Album) { pick { closeNowPlaying(); router.showAlbum(track) } }
        if (showsArtist) MenuItem("Go to Artist", Icons.Filled.Mic) { pick { closeNowPlaying(); router.showArtist(track) } }
        MenuItem("Share", Icons.Filled.Share) {
            pick {
                val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, track.externalUrl)
                context.startActivity(Intent.createChooser(send, null))
            }
        }
        MenuItem("Open in YouTube", Icons.AutoMirrored.Filled.OpenInNew) { pick { uriHandler.openUri(track.externalUrl) } }
        removal?.let {
            HorizontalDivider()
            MenuItem(it.title, Icons.Filled.Delete, isDestructive = true) { pick(it.action) }
        }
    }
}

@Composable
fun MenuItem(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, isDestructive: Boolean = false, onClick: () -> Unit) {
    val color = if (isDestructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface
    DropdownMenuItem(
        text = { Text(title, color = color) },
        leadingIcon = { Icon(icon, contentDescription = null, tint = color) },
        onClick = onClick,
    )
}

/**
 * A song in a list: artwork, title, artist and length, with a ⋯ menu that a long press opens
 * too. The playing song's title is tinted.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun TrackRow(
    track: Track,
    isCurrent: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    rank: Int? = null,
    subtitle: String? = track.artist,
    showsArtwork: Boolean = true,
    leading: (@Composable () -> Unit)? = null,
    showsAlbum: Boolean = true,
    showsArtist: Boolean = true,
    removal: TrackRemoval? = null,
    hasMenu: Boolean = true,
) {
    var isMenuShown by remember { mutableStateOf(false) }
    Row(
        modifier = modifier
            .fillMaxWidth()
            .combinedClickable(onClick = onClick, onLongClick = if (hasMenu) ({ isMenuShown = true }) else null)
            .padding(start = Spacing.large, end = if (hasMenu) Spacing.xSmall else Spacing.large)
            .padding(vertical = Spacing.small),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.medium),
    ) {
        if (rank != null) {
            Text(
                rank.toString(),
                modifier = Modifier.width(Layout.chartRankWidth),
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
        leading?.invoke()
        if (showsArtwork) ArtworkImage(track.artworkUrl, Modifier.size(ArtworkSize.row), cornerRadius = Radius.small)
        Column(Modifier.weight(1f)) {
            Text(
                track.title,
                style = MaterialTheme.typography.bodyLarge,
                color = if (isCurrent) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            subtitle?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        track.duration?.let { seconds ->
            Text(
                TimeFormatting.string(seconds),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (hasMenu) {
            Box {
                IconButton(onClick = { isMenuShown = true }) {
                    Icon(Icons.Filled.MoreVert, contentDescription = "More for ${track.title}")
                }
                TrackMenu(
                    track = track,
                    expanded = isMenuShown,
                    onDismiss = { isMenuShown = false },
                    showsAlbum = showsAlbum,
                    showsArtist = showsArtist,
                    removal = removal,
                )
            }
        }
    }
}

/** An album's track number, or a sound symbol while it plays. */
@Composable
fun TrackNumber(number: Int, isCurrent: Boolean) {
    Box(Modifier.widthIn(min = Layout.chartRankWidth), contentAlignment = Alignment.Center) {
        if (isCurrent) {
            Icon(Icons.Filled.GraphicEq, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        } else {
            Text(number.toString(), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** A song as a card in a carousel: artwork, title and artist, with the long-press menu. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun TrackCard(track: Track, onClick: () -> Unit, modifier: Modifier = Modifier) {
    var isMenuShown by remember { mutableStateOf(false) }
    val side = cardSide()
    Column(
        modifier = modifier
            .width(side)
            .combinedClickable(onClick = onClick, onLongClick = { isMenuShown = true }),
        verticalArrangement = Arrangement.spacedBy(Spacing.small),
    ) {
        Box {
            ArtworkImage(track.artworkUrl, Modifier.size(side), cornerRadius = Radius.medium)
            TrackMenu(track, expanded = isMenuShown, onDismiss = { isMenuShown = false })
        }
        Column {
            Text(track.title, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                track.artist,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/** Cards in wide windows are larger, since people view the screen from further away. */
@Composable
fun cardSide(): Dp = if (isWideWindow()) ArtworkSize.cardLarge else ArtworkSize.card

/** Windows at least as wide as a small tablet. */
@Composable
fun isWideWindow(): Boolean =
    with(LocalDensity.current) { LocalWindowInfo.current.containerSize.width.toDp() } >= Layout.wideLayoutMinWidth.dp

/** Songs as a row of cards, swiped through sideways. */
@Composable
fun TrackCarousel(tracks: List<Track>, onPlay: (Int) -> Unit) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = Spacing.large),
        horizontalArrangement = Arrangement.spacedBy(Spacing.large),
    ) {
        itemsIndexed(tracks, key = { index, track -> "$index#${track.id}" }) { index, track ->
            TrackCard(track, onClick = { onPlay(index) })
        }
    }
}

/** Songs in columns of four, swiped through sideways, like Apple Music's Top Songs. The next
 *  column peeks in, so the row clearly scrolls. */
@Composable
fun SongColumns(tracks: List<Track>, row: @Composable (Int, Track) -> Unit) {
    BoxWithConstraints {
        val columnWidth = if (isWideWindow()) Layout.wideSongColumnWidth else maxWidth - Spacing.large - Layout.carouselPeek
        LazyRow(contentPadding = PaddingValues(end = Spacing.large)) {
            val columns = tracks.withIndex().chunked(Layout.songColumnRows)
            items(columns.size) { column ->
                Column(Modifier.width(columnWidth)) {
                    columns[column].forEach { (index, track) -> row(index, track) }
                }
            }
        }
    }
}

/** Play and Shuffle side by side, under an album or playlist's header. */
@Composable
fun PlayShuffleButtons(enabled: Boolean = true, onPlay: (shuffled: Boolean) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.medium)) {
        FilledTonalButton(onClick = { onPlay(false) }, enabled = enabled, modifier = Modifier.widthIn(min = Layout.playButtonMinWidth)) {
            Icon(Icons.Filled.PlayArrow, contentDescription = null)
            Spacer(Modifier.width(Spacing.small))
            Text("Play")
        }
        FilledTonalButton(onClick = { onPlay(true) }, enabled = enabled, modifier = Modifier.widthIn(min = Layout.playButtonMinWidth)) {
            Icon(Icons.Filled.Shuffle, contentDescription = null)
            Spacer(Modifier.width(Spacing.small))
            Text("Shuffle")
        }
    }
}

/** A small spinner where a shelf's content will be. */
@Composable
fun ShelfLoading() {
    Box(Modifier.fillMaxWidth().height(Layout.shelfLoadingHeight), contentAlignment = Alignment.Center) {
        CircularProgressIndicator()
    }
}

/** A shelf's error, in a line, with Try Again when it might help. */
@Composable
fun InlineError(error: AppError, onRetry: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(Radius.large))
            .padding(Spacing.large),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.medium),
    ) {
        Icon(error.icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Column(Modifier.weight(1f)) {
            Text(error.title, style = MaterialTheme.typography.titleSmall)
            Text(error.message, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (error.isRetryable) TextButton(onClick = onRetry) { Text("Try Again") }
    }
}

val PlaylistPrivacy.icon
    get() = when (this) {
        PlaylistPrivacy.Private -> Icons.Filled.Lock
        PlaylistPrivacy.Unlisted -> Icons.Filled.Link
        PlaylistPrivacy.Public -> Icons.Filled.Public
    }

/** A playlist in a list: artwork, name, visibility and how many songs. */
@Composable
fun PlaylistRow(playlist: Playlist, modifier: Modifier = Modifier, trailing: @Composable RowScope.() -> Unit = {}) {
    Row(
        modifier = modifier.fillMaxWidth().padding(horizontal = Spacing.large, vertical = Spacing.small),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.medium),
    ) {
        ArtworkImage(playlist.artworkUrl, Modifier.size(ArtworkSize.row), cornerRadius = Radius.small)
        Column(Modifier.weight(1f)) {
            Text(playlist.title, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
                Icon(
                    playlist.privacy.icon,
                    contentDescription = playlist.privacy.title,
                    modifier = Modifier.size(Layout.inlineIconSide),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    songCount(playlist.itemCount),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        trailing()
    }
}

/** A playlist as a card: artwork, name and how many songs. */
@Composable
fun PlaylistCard(playlist: Playlist, onClick: () -> Unit) {
    val side = cardSide()
    Column(
        modifier = Modifier.width(side).clickable(onClick = onClick),
        verticalArrangement = Arrangement.spacedBy(Spacing.small),
    ) {
        ArtworkImage(playlist.artworkUrl, Modifier.size(side), cornerRadius = Radius.medium)
        Column {
            Text(playlist.title, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                songCount(playlist.itemCount),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
