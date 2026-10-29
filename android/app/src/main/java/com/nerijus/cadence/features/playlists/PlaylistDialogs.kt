package com.nerijus.cadence.features.playlists

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.PlaylistAdd
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import com.nerijus.cadence.app.LocalAppContainer
import com.nerijus.cadence.config.YouTubeApiLimits
import com.nerijus.cadence.designsystem.Layout
import com.nerijus.cadence.designsystem.Motion
import com.nerijus.cadence.designsystem.Palette
import com.nerijus.cadence.designsystem.Spacing
import com.nerijus.cadence.designsystem.components.EmptyState
import com.nerijus.cadence.designsystem.components.ErrorDialog
import com.nerijus.cadence.designsystem.components.ErrorState
import com.nerijus.cadence.designsystem.components.LoadingState
import com.nerijus.cadence.designsystem.components.PlaylistRow
import com.nerijus.cadence.designsystem.components.SectionHeader
import com.nerijus.cadence.designsystem.components.TrackRow
import com.nerijus.cadence.designsystem.components.icon
import com.nerijus.cadence.features.account.ConnectAccountButton
import com.nerijus.cadence.model.AppError
import com.nerijus.cadence.model.LoadState
import com.nerijus.cadence.model.PlaybackFailure
import com.nerijus.cadence.model.Playlist
import com.nerijus.cadence.model.PlaylistPrivacy
import com.nerijus.cadence.model.Track
import com.nerijus.cadence.model.songCount
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** A name and visibility for a new playlist. */
@Composable
fun CreatePlaylistDialog(onDismiss: () -> Unit, onCreated: (Playlist) -> Unit = {}) {
    val library = LocalAppContainer.current.library
    val scope = rememberCoroutineScope()
    var title by remember { mutableStateOf("") }
    var privacy by remember { mutableStateOf(PlaylistPrivacy.Private) }
    var isSaving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<AppError?>(null) }
    val trimmed = title.trim()
    val isTooLong = trimmed.length > YouTubeApiLimits.MAX_PLAYLIST_TITLE_LENGTH
    val canSave = trimmed.isNotEmpty() && !isTooLong && !isSaving

    fun save() {
        if (!canSave) return
        isSaving = true
        scope.launch {
            try {
                val playlist = library.createPlaylist(trimmed, privacy)
                onCreated(playlist)
                onDismiss()
            } catch (failure: Exception) {
                error = AppError.from(failure)
            } finally {
                isSaving = false
            }
        }
    }

    AlertDialog(
        onDismissRequest = { if (!isSaving) onDismiss() },
        title = { Text("New Playlist") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.medium)) {
                OutlinedTextField(
                    value = title,
                    onValueChange = { title = it },
                    label = { Text("Playlist name") },
                    singleLine = true,
                    isError = isTooLong,
                    supportingText = if (isTooLong) {
                        { Text("Names can be up to ${YouTubeApiLimits.MAX_PLAYLIST_TITLE_LENGTH} characters.") }
                    } else {
                        null
                    },
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { save() }),
                )
                Text("Visibility", style = MaterialTheme.typography.labelLarge)
                PlaylistPrivacy.entries.forEach { option ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .selectable(selected = privacy == option, role = Role.RadioButton) { privacy = option },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(selected = privacy == option, onClick = null)
                        Icon(option.icon, contentDescription = null, modifier = Modifier.padding(horizontal = Spacing.small))
                        Text(option.title)
                    }
                }
                Text(privacy.explanation, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        confirmButton = {
            if (isSaving) {
                CircularProgressIndicator(Modifier.size(Layout.inlineProgressSide), strokeWidth = Layout.inlineProgressStroke)
            } else {
                TextButton(onClick = ::save, enabled = canSave) { Text("Create") }
            }
        },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !isSaving) { Text("Cancel") } },
    )
    ErrorDialog(error) { error = null }
}

/** The rename prompt and the delete confirmation for a playlist, and the work behind them. */
@Composable
fun PlaylistEditor(renaming: Playlist?, deleting: Playlist?, onDone: () -> Unit, onDeleted: () -> Unit = {}) {
    val library = LocalAppContainer.current.library
    val scope = rememberCoroutineScope()
    var error by remember { mutableStateOf<AppError?>(null) }

    renaming?.let { playlist ->
        var title by remember(playlist.id) { mutableStateOf(playlist.title) }
        val trimmed = title.trim()
        val canRename = trimmed.isNotEmpty() && trimmed.length <= YouTubeApiLimits.MAX_PLAYLIST_TITLE_LENGTH && trimmed != playlist.title
        AlertDialog(
            onDismissRequest = onDone,
            title = { Text("Rename Playlist") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.small)) {
                    Text("Names can be up to ${YouTubeApiLimits.MAX_PLAYLIST_TITLE_LENGTH} characters.")
                    OutlinedTextField(value = title, onValueChange = { title = it }, label = { Text("Playlist name") }, singleLine = true)
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        onDone()
                        scope.launch {
                            try {
                                library.rename(playlist, trimmed)
                            } catch (failure: Exception) {
                                error = AppError.from(failure)
                            }
                        }
                    },
                    enabled = canRename,
                ) { Text("Rename") }
            },
            dismissButton = { TextButton(onClick = onDone) { Text("Cancel") } },
        )
    }

    deleting?.let { playlist ->
        AlertDialog(
            onDismissRequest = onDone,
            title = { Text("Delete “${playlist.title}”?") },
            text = {
                Text("This deletes the playlist from your YouTube account and can't be undone. The songs themselves aren't affected.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        onDone()
                        scope.launch {
                            try {
                                library.delete(playlist)
                                onDeleted()
                            } catch (failure: Exception) {
                                error = AppError.from(failure)
                            }
                        }
                    },
                ) { Text("Delete Playlist", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = onDone) { Text("Cancel") } },
        )
    }
    ErrorDialog(error) { error = null }
}

private const val TITLES_SHOWN = 3

/** Picks a playlist for one or more songs and adds them in order, with progress for several. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddToPlaylistSheet(tracks: List<Track>, onDismiss: () -> Unit) {
    val container = LocalAppContainer.current
    val library = container.library
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var savingPlaylistId by remember { mutableStateOf<String?>(null) }
    var addedCount by remember { mutableIntStateOf(0) }
    var addedPlaylistId by remember { mutableStateOf<String?>(null) }
    /** Songs YouTube had no video for, which were left out. */
    var missingCount by remember { mutableIntStateOf(0) }
    var isShowingMissing by remember { mutableStateOf(false) }
    var isCreating by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<AppError?>(null) }
    val isSignedIn = container.auth.isSignedIn

    LaunchedEffect(isSignedIn) {
        if (isSignedIn && library.playlists !is LoadState.Loaded) library.loadPlaylists()
    }

    /** One YouTube has no video for is skipped and counted; any other failure stops, leaving the
     *  songs before it added. */
    fun add(playlist: Playlist) {
        savingPlaylistId = playlist.id
        addedCount = 0
        missingCount = 0
        scope.launch {
            try {
                for (track in tracks) {
                    try {
                        library.add(track, playlist)
                    } catch (failure: AppError.Playback) {
                        if (failure.failure != PlaybackFailure.NoYouTubeMatch) throw failure
                        missingCount += 1
                    }
                    addedCount += 1
                }
                addedPlaylistId = playlist.id
                if (missingCount > 0) {
                    isShowingMissing = true
                } else {
                    delay(Motion.confirmationHold)
                    onDismiss()
                }
            } catch (failure: Exception) {
                error = AppError.from(failure)
            } finally {
                savingPlaylistId = null
            }
        }
    }

    ModalBottomSheet(onDismissRequest = { if (savingPlaylistId == null) onDismiss() }, sheetState = sheetState) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding()) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(start = Spacing.large, end = Spacing.small),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Add to Playlist", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                if (isSignedIn) {
                    TextButton(onClick = { isCreating = true }, enabled = savingPlaylistId == null) {
                        Icon(Icons.Filled.Add, contentDescription = null)
                        Text("New Playlist")
                    }
                }
            }
            // The song, or how many songs and the first few titles.
            val single = tracks.singleOrNull()
            if (single != null) {
                TrackRow(single, isCurrent = false, onClick = {}, hasMenu = false)
            } else {
                Column(Modifier.padding(horizontal = Spacing.large, vertical = Spacing.small)) {
                    Text(songCount(tracks.size), style = MaterialTheme.typography.bodyLarge)
                    Text(
                        tracks.take(TITLES_SHOWN).joinToString(", ") { it.title },
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            Box(Modifier.fillMaxWidth().weight(1f, fill = false)) {
                when {
                    !container.auth.isConfigured -> ErrorState(AppError.MissingClientId, onRetry = {})
                    !isSignedIn -> EmptyState(
                        title = "Connect to Save Songs",
                        icon = Icons.AutoMirrored.Filled.PlaylistAdd,
                        message = "Connect your YouTube account to add songs to your playlists.",
                        modifier = Modifier.fillMaxSize(),
                    ) { ConnectAccountButton(showsSetupHint = false) }
                    else -> when (val state = library.playlists) {
                        LoadState.Idle, LoadState.Loading -> LoadingState("Loading your playlists…")
                        is LoadState.Failed -> ErrorState(state.error, onRetry = { scope.launch { library.loadPlaylists() } })
                        is LoadState.Loaded -> LazyColumn {
                            item { SectionHeader("Your Playlists", Modifier.padding(horizontal = Spacing.large, vertical = Spacing.small)) }
                            if (state.value.isEmpty()) {
                                item {
                                    TextButton(onClick = { isCreating = true }, modifier = Modifier.padding(horizontal = Spacing.small)) {
                                        Text("Create Your First Playlist")
                                    }
                                }
                            }
                            items(state.value, key = { it.id }) { playlist ->
                                PlaylistRow(
                                    playlist,
                                    Modifier.clickable(enabled = savingPlaylistId == null) { add(playlist) },
                                ) {
                                    if (savingPlaylistId == playlist.id) {
                                        if (tracks.size > 1) {
                                            Text(
                                                "$addedCount of ${tracks.size}",
                                                style = MaterialTheme.typography.labelMedium,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            )
                                        }
                                        CircularProgressIndicator(Modifier.size(Layout.inlineProgressSide), strokeWidth = Layout.inlineProgressStroke)
                                    } else if (addedPlaylistId == playlist.id) {
                                        Icon(Icons.Filled.CheckCircle, contentDescription = "Added", tint = Palette.success)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (isCreating) CreatePlaylistDialog(onDismiss = { isCreating = false }, onCreated = ::add)
    if (isShowingMissing) {
        AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text("Some Songs Weren't Added") },
            text = {
                Text("YouTube has no video for ${songCount(missingCount)}, so ${if (missingCount == 1) "it was" else "they were"} left out. The rest were added.")
            },
            confirmButton = { TextButton(onClick = onDismiss) { Text("OK") } },
        )
    }
    ErrorDialog(error) { error = null }
}
