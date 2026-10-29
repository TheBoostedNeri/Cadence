package com.nerijus.cadence.features.playlists

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import com.nerijus.cadence.app.LocalAppContainer
import com.nerijus.cadence.app.LocalPlayer
import com.nerijus.cadence.app.LocalRouter
import com.nerijus.cadence.app.Route
import com.nerijus.cadence.designsystem.ArtworkSize
import com.nerijus.cadence.designsystem.Radius
import com.nerijus.cadence.designsystem.Spacing
import com.nerijus.cadence.designsystem.components.ArtworkImage
import com.nerijus.cadence.designsystem.components.EmptyState
import com.nerijus.cadence.designsystem.components.ErrorDialog
import com.nerijus.cadence.designsystem.components.ErrorState
import com.nerijus.cadence.designsystem.components.LoadingState
import com.nerijus.cadence.designsystem.components.MenuItem
import com.nerijus.cadence.designsystem.components.PlayShuffleButtons
import com.nerijus.cadence.designsystem.components.PlaylistRow
import com.nerijus.cadence.designsystem.components.Refreshable
import com.nerijus.cadence.designsystem.components.SubPage
import com.nerijus.cadence.designsystem.components.TabPage
import com.nerijus.cadence.designsystem.components.TrackRemoval
import com.nerijus.cadence.designsystem.components.TrackRow
import com.nerijus.cadence.designsystem.components.icon
import com.nerijus.cadence.designsystem.components.rememberLoader
import com.nerijus.cadence.features.account.ConnectAccountButton
import com.nerijus.cadence.model.AppError
import com.nerijus.cadence.model.LoadState
import com.nerijus.cadence.model.Playlist
import com.nerijus.cadence.model.PlaylistEntry
import kotlinx.coroutines.launch

/** The user's YouTube playlists. Long-press one, or use its ⋯, to rename or delete it. */
@Composable
fun PlaylistsScreen() {
    val container = LocalAppContainer.current
    val library = container.library
    val router = LocalRouter.current
    val isSignedIn = container.auth.isSignedIn
    var isCreating by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf<Playlist?>(null) }
    var deleting by remember { mutableStateOf<Playlist?>(null) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(isSignedIn) {
        if (isSignedIn && library.playlists !is LoadState.Loaded) library.loadPlaylists()
    }

    TabPage(
        "Playlists",
        actions = {
            if (isSignedIn) {
                IconButton(onClick = { isCreating = true }) { Icon(Icons.Filled.Add, contentDescription = "New Playlist") }
            }
        },
    ) {
        when {
            !container.auth.isConfigured -> ErrorState(AppError.MissingClientId, onRetry = {})
            !isSignedIn -> EmptyState(
                title = "Your Playlists",
                icon = Icons.AutoMirrored.Filled.QueueMusic,
                message = "Connect your YouTube account to see your liked music, your playlists and new releases from channels you subscribe to.",
            ) { ConnectAccountButton(showsSetupHint = false) }
            else -> when (val state = library.playlists) {
                LoadState.Idle, LoadState.Loading -> LoadingState("Loading your playlists…")
                is LoadState.Failed -> ErrorState(state.error, onRetry = { scope.launch { library.loadPlaylists() } })
                is LoadState.Loaded -> if (state.value.isEmpty()) {
                    EmptyState(
                        title = "No Playlists Yet",
                        icon = Icons.AutoMirrored.Filled.QueueMusic,
                        message = "Create a playlist, then long-press any song to add it.",
                    ) {
                        Button(onClick = { isCreating = true }) { Text("New Playlist") }
                    }
                } else {
                    var isRefreshing by remember { mutableStateOf(false) }
                    Refreshable(
                        isRefreshing = isRefreshing,
                        onRefresh = {
                            isRefreshing = true
                            scope.launch {
                                library.loadPlaylists()
                                isRefreshing = false
                            }
                        },
                    ) {
                        LazyColumn {
                            items(state.value, key = { it.id }) { playlist ->
                                EditablePlaylistRow(
                                    playlist,
                                    onOpen = { router.push(Route.PlaylistDetail(playlist)) },
                                    onRename = { renaming = playlist },
                                    onDelete = { deleting = playlist },
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    if (isCreating) CreatePlaylistDialog(onDismiss = { isCreating = false })
    PlaylistEditor(renaming = renaming, deleting = deleting, onDone = { renaming = null; deleting = null })
    ErrorDialog(library.refreshError) { library.refreshError = null }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun EditablePlaylistRow(playlist: Playlist, onOpen: () -> Unit, onRename: () -> Unit, onDelete: () -> Unit) {
    var isMenuShown by remember { mutableStateOf(false) }
    PlaylistRow(
        playlist,
        Modifier.combinedClickable(onClick = onOpen, onLongClick = { isMenuShown = true }),
    ) {
        Box {
            IconButton(onClick = { isMenuShown = true }) { Icon(Icons.Filled.MoreVert, contentDescription = "More for ${playlist.title}") }
            PlaylistEditMenu(isMenuShown, onDismiss = { isMenuShown = false }, onRename = onRename, onDelete = onDelete)
        }
    }
}

/** Rename and Delete for one of the user's playlists. */
@Composable
fun PlaylistEditMenu(expanded: Boolean, onDismiss: () -> Unit, onRename: () -> Unit, onDelete: () -> Unit) {
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
        MenuItem("Rename…", Icons.Filled.Edit) {
            onDismiss()
            onRename()
        }
        MenuItem("Delete Playlist…", Icons.Filled.Delete, isDestructive = true) {
            onDismiss()
            onDelete()
        }
    }
}

/** A playlist's songs, with Play and Shuffle. Songs can be removed from their ⋯ menu. */
@Composable
fun PlaylistDetailScreen(playlist: Playlist) {
    val library = LocalAppContainer.current.library
    val player = LocalPlayer.current
    val router = LocalRouter.current
    val scope = rememberCoroutineScope()
    // Picks up a new name as soon as it's saved.
    val current = library.current(playlist)
    val entries = rememberLoader("entries") { library.entries(playlist) }
    var isMenuShown by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf<Playlist?>(null) }
    var deleting by remember { mutableStateOf<Playlist?>(null) }
    var actionError by remember { mutableStateOf<AppError?>(null) }
    val tracks = entries.value?.map(PlaylistEntry::track).orEmpty()

    /** Removes at once and puts the song back if YouTube rejects the change. */
    fun remove(entry: PlaylistEntry) {
        val items = entries.value ?: return
        entries.replace(items - entry)
        scope.launch {
            try {
                library.remove(entry, playlist)
            } catch (error: Exception) {
                entries.replace(items)
                actionError = AppError.from(error)
            }
        }
    }

    SubPage(
        current.title,
        actions = {
            Box {
                IconButton(onClick = { isMenuShown = true }) { Icon(Icons.Filled.MoreVert, contentDescription = "More") }
                PlaylistEditMenu(isMenuShown, onDismiss = { isMenuShown = false }, onRename = { renaming = current }, onDelete = { deleting = current })
            }
        },
    ) {
        Refreshable(isRefreshing = entries.isRefreshing, onRefresh = entries::reload) {
            LazyColumn(contentPadding = PaddingValues(bottom = Spacing.large)) {
                item {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(vertical = Spacing.large),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(Spacing.large),
                    ) {
                        ArtworkImage(current.largeArtworkUrl ?: current.artworkUrl, Modifier.size(ArtworkSize.header), cornerRadius = Radius.large)
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(current.title, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(current.privacy.icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                Text(
                                    " ${current.privacy.title}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                        PlayShuffleButtons(enabled = tracks.isNotEmpty()) { shuffled ->
                            player.play(if (shuffled) tracks.shuffled() else tracks)
                        }
                    }
                }
                when (val state = entries.state) {
                    LoadState.Idle, LoadState.Loading -> item { LoadingState("Loading songs…") }
                    is LoadState.Failed -> item { ErrorState(state.error, onRetry = entries::reload) }
                    is LoadState.Loaded -> if (state.value.isEmpty()) {
                        item {
                            EmptyState(
                                title = "This Playlist Is Empty",
                                icon = Icons.Filled.MusicNote,
                                message = "Long-press any song in Home, Search or Recents to add it here.",
                            )
                        }
                    } else {
                        itemsIndexed(state.value, key = { _, entry -> entry.id }) { index, entry ->
                            TrackRow(
                                entry.track,
                                isCurrent = entry.track.isSameSong(player.currentTrack),
                                onClick = { player.play(tracks, index) },
                                removal = TrackRemoval("Remove from Playlist") { remove(entry) },
                            )
                        }
                    }
                }
            }
        }
    }

    // A deleted playlist's page closes.
    PlaylistEditor(renaming = renaming, deleting = deleting, onDone = { renaming = null; deleting = null }, onDeleted = { router.pop() })
    ErrorDialog(actionError) { actionError = null }
}
