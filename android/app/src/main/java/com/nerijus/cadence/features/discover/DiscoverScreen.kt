package com.nerijus.cadence.features.discover

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.PlaylistAdd
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import com.nerijus.cadence.app.LocalAppContainer
import com.nerijus.cadence.app.LocalPlayer
import com.nerijus.cadence.app.LocalRouter
import com.nerijus.cadence.app.Route
import com.nerijus.cadence.catalog.MusicGenre
import com.nerijus.cadence.designsystem.Layout
import com.nerijus.cadence.designsystem.Opacity
import com.nerijus.cadence.designsystem.Palette
import com.nerijus.cadence.designsystem.Radius
import com.nerijus.cadence.designsystem.Spacing
import com.nerijus.cadence.designsystem.components.EmptyState
import com.nerijus.cadence.designsystem.components.ErrorState
import com.nerijus.cadence.designsystem.components.InlineError
import com.nerijus.cadence.designsystem.components.LoadingState
import com.nerijus.cadence.designsystem.components.PlayShuffleButtons
import com.nerijus.cadence.designsystem.components.Refreshable
import com.nerijus.cadence.designsystem.components.SectionHeader
import com.nerijus.cadence.designsystem.components.ShelfLoading
import com.nerijus.cadence.designsystem.components.SongColumns
import com.nerijus.cadence.designsystem.components.SubPage
import com.nerijus.cadence.designsystem.components.TabPage
import com.nerijus.cadence.designsystem.components.TrackRow
import com.nerijus.cadence.designsystem.components.rememberLoader
import com.nerijus.cadence.model.LoadState
import com.nerijus.cadence.model.Track

/** What's trending on YouTube, then every genre to explore, like Apple Music's Browse. Genres
 *  come from Apple's charts and play through YouTube. */
@Composable
fun DiscoverScreen() {
    val model = LocalAppContainer.current.discover
    LaunchedEffect(model) { model.loadIfNeeded() }

    TabPage("Discover") {
        Refreshable(isRefreshing = model.isRefreshing, onRefresh = model::reload) {
            BoxWithConstraints {
                // As many tiles across as fit at their narrowest.
                val columns = maxOf(
                    1,
                    ((maxWidth - Spacing.large * 2 + Spacing.medium) / (Layout.genreTileMinWidth + Spacing.medium)).toInt(),
                )
                LazyColumn(
                    contentPadding = PaddingValues(vertical = Spacing.large),
                    verticalArrangement = Arrangement.spacedBy(Spacing.medium),
                ) {
                    item { TrendingSection(model) }
                    item {
                        SectionHeader("Browse by Genre", Modifier.padding(horizontal = Spacing.large).padding(top = Spacing.large))
                    }
                    val rows = MusicGenre.all.withIndex().chunked(columns)
                    items(rows.size) { row ->
                        Row(
                            modifier = Modifier.padding(horizontal = Spacing.large),
                            horizontalArrangement = Arrangement.spacedBy(Spacing.medium),
                        ) {
                            rows[row].forEach { (index, genre) ->
                                Box(Modifier.weight(1f)) { GenreTile(genre, Palette.genreTints[index % Palette.genreTints.size]) }
                            }
                            repeat(columns - rows[row].size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TrendingSection(model: DiscoverModel) {
    val player = LocalPlayer.current
    val router = LocalRouter.current
    when (val state = model.trending) {
        LoadState.Idle, LoadState.Loading -> Column(verticalArrangement = Arrangement.spacedBy(Spacing.medium)) {
            SectionHeader("Trending Now", Modifier.padding(horizontal = Spacing.large))
            ShelfLoading()
        }
        is LoadState.Failed -> Column(
            modifier = Modifier.padding(horizontal = Spacing.large),
            verticalArrangement = Arrangement.spacedBy(Spacing.medium),
        ) {
            SectionHeader("Trending Now")
            InlineError(state.error, model::reload)
        }
        // Some regions have no chart; the genres still work.
        is LoadState.Loaded -> if (state.value.isNotEmpty()) {
            val tracks = state.value
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.medium)) {
                SectionHeader(
                    "Trending Now",
                    Modifier.padding(start = Spacing.large, end = Spacing.small),
                    subtitle = model.chartDescription,
                    actionTitle = "See All",
                    onAction = { router.push(Route.TrendingChart) },
                )
                SongColumns(tracks.take(Layout.songColumnsShown)) { index, track ->
                    TrackRow(
                        track,
                        isCurrent = track.isSameSong(player.currentTrack),
                        onClick = { player.play(tracks, index) },
                        rank = index + 1,
                    )
                }
            }
        }
    }
}

/** A colorful tile for a genre, its symbol tucked into the corner, like Apple Music's Browse. */
@Composable
private fun GenreTile(genre: MusicGenre, tint: Color) {
    val router = LocalRouter.current
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(Layout.genreTileHeight)
            .clip(RoundedCornerShape(Radius.large))
            .background(Brush.verticalGradient(listOf(tint, tint.copy(alpha = Opacity.genreTileBottom))))
            .clickable { router.push(Route.Genre(genre)) },
    ) {
        Icon(
            genre.icon,
            contentDescription = null,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(Spacing.medium)
                .size(Layout.genreSymbolSide),
            tint = Palette.onPlayer.copy(alpha = Opacity.genreSymbol),
        )
        Text(
            genre.name,
            modifier = Modifier.align(Alignment.BottomStart).padding(Spacing.medium),
            style = MaterialTheme.typography.titleMedium,
            color = Palette.onPlayer,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** The whole trending chart, from Trending Now's See All. */
@Composable
fun TrendingChartScreen() {
    val model = LocalAppContainer.current.discover
    val tracks = (model.trending as? LoadState.Loaded)?.value.orEmpty()
    SelectableSongPage("Trending Now", tracks, ranked = true) {
        Text(
            model.chartDescription,
            modifier = Modifier.padding(horizontal = Spacing.large, vertical = Spacing.small),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** A genre's best-selling songs from Apple's charts, each played through YouTube. */
@Composable
fun GenreScreen(genre: MusicGenre) {
    val catalog = LocalAppContainer.current.catalog
    val player = LocalPlayer.current
    val songs = rememberLoader("genre") { catalog.topSongs(genre) }
    when (val state = songs.state) {
        LoadState.Idle, LoadState.Loading -> SubPage(genre.name) { LoadingState("Finding ${genre.name} songs…") }
        is LoadState.Failed -> SubPage(genre.name) { ErrorState(state.error, onRetry = songs::reload) }
        is LoadState.Loaded -> if (state.value.isEmpty()) {
            SubPage(genre.name) {
                EmptyState(
                    title = "No Songs Here Yet",
                    icon = genre.icon,
                    message = "Apple has no ${genre.name} chart for your region. Try another genre.",
                )
            }
        } else {
            val tracks = state.value
            SelectableSongPage(genre.name, tracks, ranked = true) {
                Box(Modifier.fillMaxWidth().padding(vertical = Spacing.small), contentAlignment = Alignment.Center) {
                    PlayShuffleButtons { shuffled -> player.play(if (shuffled) tracks.shuffled() else tracks) }
                }
            }
        }
    }
}

/**
 * A ranked song list with Select, like Apple Music's: picked songs are added to a playlist
 * together. Otherwise each row plays from there, with its ⋯ menu.
 */
@Composable
fun SelectableSongPage(title: String, tracks: List<Track>, ranked: Boolean, header: @Composable () -> Unit) {
    val player = LocalPlayer.current
    val router = LocalRouter.current
    var isSelecting by rememberSaveable { mutableStateOf(false) }
    // Positions rather than songs, since a chart can list the same song twice.
    var selection by remember { mutableStateOf(emptySet<Int>()) }
    val isAllSelected = selection.size == tracks.size
    fun endSelecting() {
        isSelecting = false
        selection = emptySet()
    }

    SubPage(
        title,
        showsBack = !isSelecting,
        actions = {
            if (isSelecting) {
                TextButton(onClick = { selection = if (isAllSelected) emptySet() else tracks.indices.toSet() }) {
                    Text(if (isAllSelected) "Deselect All" else "Select All")
                }
                TextButton(onClick = ::endSelecting) { Text("Done") }
            } else if (tracks.isNotEmpty()) {
                IconButton(onClick = { isSelecting = true }) {
                    Icon(Icons.Outlined.CheckCircle, contentDescription = "Select")
                }
                IconButton(onClick = { player.play(tracks) }) {
                    Icon(Icons.Filled.PlayArrow, contentDescription = "Play All")
                }
            }
        },
    ) {
        Box(Modifier.fillMaxSize()) {
            LazyColumn(contentPadding = PaddingValues(bottom = if (isSelecting) Layout.selectionBarSpace else Spacing.none)) {
                item { header() }
                itemsIndexed(tracks, key = { index, track -> "$index#${track.id}" }) { index, track ->
                    val isSelected = index in selection
                    TrackRow(
                        track = track,
                        isCurrent = track.isSameSong(player.currentTrack),
                        onClick = {
                            if (isSelecting) {
                                selection = if (isSelected) selection - index else selection + index
                            } else {
                                player.play(tracks, index)
                            }
                        },
                        rank = if (ranked) index + 1 else null,
                        hasMenu = !isSelecting,
                        modifier = Modifier.semantics { if (isSelecting) selected = isSelected },
                        leading = if (isSelecting) {
                            {
                                Icon(
                                    if (isSelected) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                                    contentDescription = null,
                                    tint = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        } else {
                            null
                        },
                    )
                }
            }
            SelectionBar(
                isSelecting = isSelecting,
                count = selection.size,
                modifier = Modifier.align(Alignment.BottomCenter),
                onAdd = {
                    router.addToPlaylist(tracks.filterIndexed { index, _ -> index in selection })
                    endSelecting()
                },
            )
        }
    }
}

/** "Add N to Playlist", rising from the bottom while songs are being picked. */
@Composable
private fun SelectionBar(isSelecting: Boolean, count: Int, modifier: Modifier, onAdd: () -> Unit) {
    AnimatedVisibility(
        visible = isSelecting,
        modifier = modifier,
        enter = slideInVertically { it } + fadeIn(),
        exit = slideOutVertically { it } + fadeOut(),
    ) {
        Row(Modifier.navigationBarsPadding().padding(Spacing.large)) {
            Button(onClick = onAdd, enabled = count > 0, modifier = Modifier.widthIn(min = Layout.buttonMaxWidth)) {
                Icon(Icons.AutoMirrored.Filled.PlaylistAdd, contentDescription = null)
                Text(if (count == 0) "  Add to Playlist" else "  Add $count to Playlist")
            }
        }
    }
}
