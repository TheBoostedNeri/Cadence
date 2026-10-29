package com.nerijus.cadence.features.player

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FastForward
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import com.nerijus.cadence.app.LocalPlayer
import com.nerijus.cadence.designsystem.ArtworkSize
import com.nerijus.cadence.designsystem.Elevation
import com.nerijus.cadence.designsystem.Layout
import com.nerijus.cadence.designsystem.Radius
import com.nerijus.cadence.designsystem.Spacing
import com.nerijus.cadence.designsystem.components.ArtworkImage

/** The bar above the tabs: the song playing, Play or Pause, and Next. Tapping it opens Now
 *  Playing. With nothing queued it says "Not Playing" and its buttons are greyed out. */
@Composable
fun MiniPlayer(modifier: Modifier = Modifier) {
    val player = LocalPlayer.current
    val track = player.currentTrack

    Surface(
        onClick = player::presentNowPlaying,
        enabled = track != null,
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = Spacing.medium, vertical = Spacing.small)
            .height(Layout.miniPlayerHeight),
        shape = RoundedCornerShape(Radius.large),
        tonalElevation = Elevation.raised,
        shadowElevation = Elevation.raised,
    ) {
        Box {
            Row(
                modifier = Modifier
                    .fillMaxHeight()
                    .padding(horizontal = Spacing.medium),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Spacing.medium),
            ) {
                ArtworkImage(track?.artworkUrl, Modifier.size(ArtworkSize.row), cornerRadius = Radius.small)
                Column(Modifier.weight(1f)) {
                    Text(
                        track?.title ?: "Not Playing",
                        style = MaterialTheme.typography.titleSmall,
                        color = if (track != null) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    track?.let {
                        Text(
                            it.artist,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
                IconButton(onClick = player::togglePlayPause, enabled = track != null) {
                    if (player.status.isActive) {
                        Icon(Icons.Filled.Pause, contentDescription = "Pause")
                    } else {
                        Icon(Icons.Filled.PlayArrow, contentDescription = "Play")
                    }
                }
                IconButton(onClick = player::next, enabled = player.hasNext) {
                    Icon(Icons.Filled.FastForward, contentDescription = "Next")
                }
            }
            if (track != null && player.duration > 0) {
                val fraction = (player.currentTime / player.duration).toFloat().coerceIn(0f, 1f)
                Box(
                    Modifier
                        .align(Alignment.BottomStart)
                        .fillMaxWidth(fraction)
                        .height(Layout.miniPlayerProgressHeight)
                        .background(MaterialTheme.colorScheme.primary),
                )
            }
        }
    }
}
