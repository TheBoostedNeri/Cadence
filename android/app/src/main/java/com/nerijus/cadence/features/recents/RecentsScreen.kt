package com.nerijus.cadence.features.recents

import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.History
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.nerijus.cadence.app.AppTab
import com.nerijus.cadence.app.LocalAppContainer
import com.nerijus.cadence.app.LocalPlayer
import com.nerijus.cadence.app.LocalRouter
import com.nerijus.cadence.designsystem.components.EmptyState
import com.nerijus.cadence.designsystem.components.TabPage
import com.nerijus.cadence.designsystem.components.TrackRemoval
import com.nerijus.cadence.designsystem.components.TrackRow

/** Songs played on this device, newest first. */
@Composable
fun RecentsScreen() {
    val recents = LocalAppContainer.current.recents
    val player = LocalPlayer.current
    val router = LocalRouter.current
    var isConfirmingClear by remember { mutableStateOf(false) }
    val tracks = recents.plays.map { it.track }

    TabPage(
        "Recently Played",
        actions = {
            if (tracks.isNotEmpty()) {
                TextButton(onClick = { isConfirmingClear = true }) { Text("Clear", color = MaterialTheme.colorScheme.error) }
            }
        },
    ) {
        if (tracks.isEmpty()) {
            EmptyState(
                title = "Nothing Played Yet",
                icon = Icons.Filled.History,
                message = "Songs you play show up here so you can jump back in.",
            ) {
                Button(onClick = { router.select(AppTab.Home) }) { Text("Browse Home") }
            }
        } else {
            LazyColumn {
                itemsIndexed(tracks, key = { _, track -> track.id }) { index, track ->
                    TrackRow(
                        track,
                        isCurrent = track.isSameSong(player.currentTrack),
                        onClick = { player.play(tracks, index) },
                        removal = TrackRemoval("Remove from Recently Played") { recents.remove(track) },
                    )
                }
            }
        }
    }

    if (isConfirmingClear) {
        AlertDialog(
            onDismissRequest = { isConfirmingClear = false },
            title = { Text("Clear history?") },
            text = { Text("This removes songs you played from this device. Your playlists aren't affected.") },
            confirmButton = {
                TextButton(onClick = {
                    isConfirmingClear = false
                    recents.clear()
                }) { Text("Clear History", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { isConfirmingClear = false }) { Text("Cancel") } },
        )
    }
}
