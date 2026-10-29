package com.nerijus.cadence.features.catalog

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Album
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import com.nerijus.cadence.app.LocalAppContainer
import com.nerijus.cadence.app.LocalPlayer
import com.nerijus.cadence.app.LocalRouter
import com.nerijus.cadence.app.Route
import com.nerijus.cadence.designsystem.ArtworkSize
import com.nerijus.cadence.designsystem.Layout
import com.nerijus.cadence.designsystem.Opacity
import com.nerijus.cadence.designsystem.Palette
import com.nerijus.cadence.designsystem.Radius
import com.nerijus.cadence.designsystem.Spacing
import com.nerijus.cadence.designsystem.TouchTarget
import com.nerijus.cadence.designsystem.backgroundGradient
import com.nerijus.cadence.designsystem.components.ArtworkImage
import com.nerijus.cadence.designsystem.components.EmptyState
import com.nerijus.cadence.designsystem.components.ErrorState
import com.nerijus.cadence.designsystem.components.LoadingState
import com.nerijus.cadence.designsystem.components.PlayShuffleButtons
import com.nerijus.cadence.designsystem.components.SectionHeader
import com.nerijus.cadence.designsystem.components.SongColumns
import com.nerijus.cadence.designsystem.components.SubPage
import com.nerijus.cadence.designsystem.components.TrackNumber
import com.nerijus.cadence.designsystem.components.TrackRow
import com.nerijus.cadence.designsystem.components.cardSide
import com.nerijus.cadence.designsystem.components.rememberLoader
import com.nerijus.cadence.model.Album
import com.nerijus.cadence.model.AlbumSummary
import com.nerijus.cadence.model.Artist
import com.nerijus.cadence.model.LoadState
import com.nerijus.cadence.model.Track
import com.nerijus.cadence.model.songCount

/** The album a song is from, or one picked from an artist's page, from Apple's catalog. Each
 *  song plays through YouTube, its video found as it comes up. */
@Composable
fun AlbumScreen(track: Track, albumId: String? = null) {
    val catalog = LocalAppContainer.current.catalog
    val album = rememberLoader("album") { if (albumId != null) catalog.album(albumId) else catalog.albumContaining(track) }
    val loaded = album.value
    SubPage(loaded?.title.orEmpty()) {
        when (val state = album.state) {
            LoadState.Idle, LoadState.Loading -> LoadingState("Finding the album…")
            is LoadState.Failed -> ErrorState(state.error, onRetry = album::reload)
            is LoadState.Loaded -> state.value?.let { AlbumContent(it, track) } ?: EmptyState(
                title = "No Album Found",
                icon = Icons.Filled.Album,
                message = "Apple's music catalog doesn't list an album for this song.",
            )
        }
    }
}

@Composable
private fun AlbumContent(album: Album, openedFrom: Track) {
    val player = LocalPlayer.current
    val router = LocalRouter.current
    val tracks = album.tracks
    LazyColumn(contentPadding = PaddingValues(bottom = Spacing.large)) {
        item {
            Column(
                modifier = Modifier.fillMaxWidth().padding(vertical = Spacing.large),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(Spacing.large),
            ) {
                ArtworkImage(album.largeArtworkUrl ?: album.artworkUrl, Modifier.size(ArtworkSize.header), cornerRadius = Radius.large)
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(album.title, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
                    TextButton(onClick = { router.showArtist(tracks.firstOrNull { it.artist == album.artist } ?: openedFrom) }) {
                        Text(album.artist, style = MaterialTheme.typography.titleMedium)
                    }
                    Text(
                        listOfNotNull(album.releaseYear?.toString(), songCount(tracks.size)).joinToString(" · "),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                PlayShuffleButtons(enabled = tracks.isNotEmpty()) { shuffled ->
                    player.play(if (shuffled) tracks.shuffled() else tracks)
                }
            }
        }
        itemsIndexed(tracks, key = { index, song -> "$index#${song.id}" }) { index, song ->
            val isCurrent = song.isSameSong(player.currentTrack)
            TrackRow(
                track = song,
                isCurrent = isCurrent,
                onClick = { player.play(tracks, index) },
                subtitle = song.artist.takeIf { it != album.artist },
                showsArtwork = false,
                leading = { TrackNumber(index + 1, isCurrent) },
                showsAlbum = false,
            )
        }
    }
}

/**
 * An artist's page, opened with "Go to Artist", laid out like Apple Music's: a large header with
 * Play, the latest release, top songs in swipeable columns, and carousels of albums, singles and
 * EPs, and releases they appear on. Everything comes from Apple's catalog.
 */
@Composable
fun ArtistScreen(track: Track) {
    val catalog = LocalAppContainer.current.catalog
    val artist = rememberLoader("artist") { catalog.artistOf(track) }
    when (val state = artist.state) {
        LoadState.Idle, LoadState.Loading -> SubPage("") { LoadingState("Finding the artist…") }
        is LoadState.Failed -> SubPage("") { ErrorState(state.error, onRetry = artist::reload) }
        is LoadState.Loaded -> state.value?.let { ArtistContent(it, track) } ?: SubPage("") {
            EmptyState(
                title = "No Artist Found",
                icon = Icons.Filled.Mic,
                message = "Apple's music catalog doesn't list this artist.",
            )
        }
    }
}

@Composable
private fun ArtistContent(artist: Artist, openedFrom: Track) {
    val player = LocalPlayer.current
    val router = LocalRouter.current
    BoxWithConstraints(Modifier.fillMaxSize().background(backgroundGradient())) {
        // As tall as the page is wide, but never more than half of it.
        val headerHeight = minOf(maxWidth, maxHeight * Layout.artistHeaderMaxHeightFraction)
        LazyColumn(
            contentPadding = PaddingValues(bottom = Spacing.xxxLarge),
            verticalArrangement = Arrangement.spacedBy(Spacing.xxLarge),
        ) {
            item { ArtistHeader(artist, Modifier.fillMaxWidth().height(headerHeight)) }
            artist.latestRelease?.let { latest -> item { LatestRelease(latest, openedFrom) } }
            if (artist.tracks.isNotEmpty()) {
                item {
                    val shown = artist.tracks.take(Layout.songColumnsShown)
                    Column(verticalArrangement = Arrangement.spacedBy(Spacing.medium)) {
                        SectionHeader(
                            "Top Songs",
                            Modifier.padding(start = Spacing.large, end = Spacing.small),
                            actionTitle = if (artist.tracks.size > shown.size) "See All" else null,
                            onAction = { router.push(Route.ArtistSongs(artist, openedFrom)) },
                        )
                        SongColumns(shown) { index, song ->
                            TrackRow(
                                song,
                                isCurrent = song.isSameSong(player.currentTrack),
                                onClick = { player.play(artist.tracks, index) },
                                subtitle = song.albumAndYear,
                                showsArtist = false,
                            )
                        }
                    }
                }
            }
            item { ReleaseShelf("Albums", artist.albums, openedFrom) }
            item { ReleaseShelf("Singles & EPs", artist.singles, openedFrom) }
            item { ReleaseShelf("Appears On", artist.appearsOn, openedFrom) }
        }
        // Back floats over the header, which runs up under the status bar.
        IconButton(
            onClick = { router.pop() },
            modifier = Modifier.windowInsetsPadding(WindowInsets.statusBars).padding(Spacing.xSmall),
            colors = IconButtonDefaults.iconButtonColors(
                containerColor = Palette.playerBackground.copy(alpha = Opacity.backdropDim),
                contentColor = Palette.onPlayer,
            ),
        ) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
        }
    }
}

/** Apple's catalog has no artist photos, so the cover of their most popular song stands in. */
@Composable
private fun ArtistHeader(artist: Artist, modifier: Modifier) {
    val player = LocalPlayer.current
    val cover = artist.tracks.firstOrNull()
    Box(modifier) {
        ArtworkImage(cover?.largeArtworkUrl ?: cover?.artworkUrl, Modifier.fillMaxSize())
        Box(
            Modifier
                .fillMaxSize()
                .background(Brush.verticalGradient(listOf(Color.Transparent, Palette.playerBackground.copy(alpha = Opacity.scrim)))),
        )
        Row(
            modifier = Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(Spacing.large),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(Spacing.medium),
        ) {
            Text(
                artist.name,
                modifier = Modifier.weight(1f).semantics { heading() },
                style = MaterialTheme.typography.displaySmall,
                color = Palette.onPlayer,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            IconButton(
                onClick = { player.play(artist.tracks) },
                enabled = artist.tracks.isNotEmpty(),
                modifier = Modifier.size(TouchTarget.secondary),
                colors = IconButtonDefaults.iconButtonColors(
                    containerColor = MaterialTheme.colorScheme.primary,
                    contentColor = MaterialTheme.colorScheme.onPrimary,
                ),
            ) {
                Icon(Icons.Filled.PlayArrow, contentDescription = "Play ${artist.name}")
            }
        }
    }
}

@Composable
private fun LatestRelease(release: AlbumSummary, openedFrom: Track) {
    val router = LocalRouter.current
    Column(Modifier.padding(horizontal = Spacing.large), verticalArrangement = Arrangement.spacedBy(Spacing.medium)) {
        SectionHeader("Latest Release")
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(Radius.large))
                .clickable { router.showAlbum(release.id, openedFrom) }
                .padding(Spacing.medium),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.medium),
        ) {
            ArtworkImage(release.largeArtworkUrl ?: release.artworkUrl, Modifier.size(ArtworkSize.latestRelease), cornerRadius = Radius.medium)
            Column(Modifier.weight(1f)) {
                release.releaseDate?.take(DATE_LENGTH)?.let {
                    Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text(release.title, style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                release.trackCount?.let {
                    Text(songCount(it), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** "2024-03-08" from Apple's full timestamp. */
private const val DATE_LENGTH = 10

@Composable
private fun ReleaseShelf(title: String, releases: List<AlbumSummary>, openedFrom: Track) {
    if (releases.isEmpty()) return
    val router = LocalRouter.current
    val side = cardSide()
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.medium)) {
        SectionHeader(title, Modifier.padding(horizontal = Spacing.large))
        LazyRow(
            contentPadding = PaddingValues(horizontal = Spacing.large),
            horizontalArrangement = Arrangement.spacedBy(Spacing.large),
        ) {
            items(releases, key = { it.id }) { release ->
                Column(
                    modifier = Modifier.width(side).clickable { router.showAlbum(release.id, openedFrom) },
                    verticalArrangement = Arrangement.spacedBy(Spacing.small),
                ) {
                    ArtworkImage(release.largeArtworkUrl ?: release.artworkUrl, Modifier.size(side), cornerRadius = Radius.medium)
                    Text(release.title, style = MaterialTheme.typography.titleSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    release.releaseYear?.let {
                        Text(it.toString(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

/** Every one of the artist's songs, from Top Songs' See All. */
@Composable
fun ArtistSongsScreen(artist: Artist) {
    val player = LocalPlayer.current
    val tracks = artist.tracks
    SubPage("Top Songs") {
        LazyColumn {
            itemsIndexed(tracks, key = { index, song -> "$index#${song.id}" }) { index, song ->
                TrackRow(
                    song,
                    isCurrent = song.isSameSong(player.currentTrack),
                    onClick = { player.play(tracks, index) },
                    subtitle = song.albumAndYear,
                    showsArtist = false,
                )
            }
        }
    }
}
