package com.nerijus.cadence.features.home

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import com.nerijus.cadence.app.AppTab
import com.nerijus.cadence.app.LocalAppContainer
import com.nerijus.cadence.app.LocalPlayer
import com.nerijus.cadence.app.LocalRouter
import com.nerijus.cadence.app.Route
import com.nerijus.cadence.designsystem.Radius
import com.nerijus.cadence.designsystem.Spacing
import com.nerijus.cadence.designsystem.components.ErrorDialog
import com.nerijus.cadence.designsystem.components.InlineError
import com.nerijus.cadence.designsystem.components.PlaylistCard
import com.nerijus.cadence.designsystem.components.Refreshable
import com.nerijus.cadence.designsystem.components.SectionHeader
import com.nerijus.cadence.designsystem.components.ShelfLoading
import com.nerijus.cadence.designsystem.components.SubPage
import com.nerijus.cadence.designsystem.components.TabPage
import com.nerijus.cadence.designsystem.components.TrackCarousel
import com.nerijus.cadence.designsystem.components.TrackRow
import com.nerijus.cadence.features.account.ConnectAccountButton
import com.nerijus.cadence.model.AddedTrack
import com.nerijus.cadence.model.LoadState
import com.nerijus.cadence.model.Track
import java.util.Calendar

private object HomeContent {
    const val RECENTS_LIMIT = 12
    const val TRENDING_PREVIEW_COUNT = 10
    const val LIST_SHELF_ROWS = 8
    const val MORNING_START_HOUR = 5
    const val AFTERNOON_START_HOUR = 12
    const val EVENING_START_HOUR = 17
}

/** Personal shelves with an account connected; a connect prompt and a Trending preview
 *  otherwise. */
@Composable
fun HomeScreen() {
    val container = LocalAppContainer.current
    val router = LocalRouter.current
    val home = container.home
    val isSignedIn = container.auth.isSignedIn

    LaunchedEffect(isSignedIn) {
        if (isSignedIn) home.loadIfNeeded()
        container.discover.loadIfNeeded()
    }

    TabPage(
        "Home",
        actions = {
            IconButton(onClick = { router.isSettingsPresented = true }) {
                Icon(Icons.Filled.Settings, contentDescription = "Settings")
            }
        },
    ) {
        Refreshable(
            isRefreshing = home.isRefreshing || container.discover.isRefreshing,
            onRefresh = {
                if (isSignedIn) home.load(force = true) else container.discover.reload()
            },
        ) {
            LazyColumn(
                contentPadding = PaddingValues(vertical = Spacing.large),
                verticalArrangement = Arrangement.spacedBy(Spacing.xxLarge),
            ) {
                if (isSignedIn) personalContent(home) else signedOutContent()
            }
        }
    }
    ErrorDialog(home.refreshError) { home.refreshError = null }
}

private fun LazyListScope.personalContent(home: HomeModel) {
    item {
        Text(
            greeting(home.firstName),
            modifier = Modifier.padding(horizontal = Spacing.large).semantics { heading() },
            style = MaterialTheme.typography.headlineMedium,
        )
    }
    item { JumpBackInShelf() }
    item {
        TrackShelf(
            title = "Liked Music",
            subtitle = "Songs you've liked on YouTube",
            state = home.liked,
            onRetry = { home.load(force = true) },
        )
    }
    item { PlaylistsShelf() }
    item { RecentlyAddedShelf(home) }
    item {
        TrackShelf(
            title = "New From Your Subscriptions",
            subtitle = "Latest music from channels you follow",
            state = home.subscriptionUploads,
            asList = true,
            onRetry = { home.load(force = true) },
        )
    }
    // A brand-new account has nothing to show yet; keep Home useful in the meantime.
    if (home.hasNoPersonalContent) item { TrendingPreview() }
}

private fun LazyListScope.signedOutContent() {
    item { JumpBackInShelf() }
    item {
        Column(
            modifier = Modifier
                .padding(horizontal = Spacing.large)
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(Radius.large))
                .padding(Spacing.large),
            verticalArrangement = Arrangement.spacedBy(Spacing.medium),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Text("  Make Home Yours", style = MaterialTheme.typography.titleMedium)
            }
            Text(
                "Connect your YouTube account to see your liked music, your playlists and new releases from channels you subscribe to.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            ConnectAccountButton()
        }
    }
    item { TrendingPreview() }
}

private fun greeting(firstName: String?): String {
    val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
    val salutation = when (hour) {
        in HomeContent.MORNING_START_HOUR until HomeContent.AFTERNOON_START_HOUR -> "Good morning"
        in HomeContent.AFTERNOON_START_HOUR until HomeContent.EVENING_START_HOUR -> "Good afternoon"
        else -> "Good evening"
    }
    return firstName?.let { "$salutation, $it" } ?: salutation
}

/** A titled shelf of songs. Empty shelves disappear; failures show an inline error. The header's
 *  action plays every song in the shelf unless given another. */
@Composable
private fun TrackShelf(
    title: String,
    state: LoadState<List<Track>>,
    onRetry: () -> Unit,
    subtitle: String? = null,
    asList: Boolean = false,
    actionTitle: String = "Play All",
    action: ((List<Track>) -> Unit)? = null,
) {
    val player = LocalPlayer.current
    when (state) {
        LoadState.Idle, LoadState.Loading -> Column(verticalArrangement = Arrangement.spacedBy(Spacing.medium)) {
            SectionHeader(title, Modifier.padding(horizontal = Spacing.large), subtitle = subtitle)
            ShelfLoading()
        }
        is LoadState.Failed -> Column(
            modifier = Modifier.padding(horizontal = Spacing.large),
            verticalArrangement = Arrangement.spacedBy(Spacing.medium),
        ) {
            SectionHeader(title, subtitle = subtitle)
            InlineError(state.error, onRetry)
        }
        is LoadState.Loaded -> if (state.value.isNotEmpty()) {
            val tracks = state.value
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.medium)) {
                SectionHeader(
                    title,
                    Modifier.padding(start = Spacing.large, end = Spacing.small),
                    subtitle = subtitle,
                    actionTitle = actionTitle,
                    onAction = { action?.invoke(tracks) ?: player.play(tracks) },
                )
                if (asList) {
                    Column {
                        tracks.take(HomeContent.LIST_SHELF_ROWS).forEachIndexed { index, track ->
                            TrackRow(track, isCurrent = track.isSameSong(player.currentTrack), onClick = { player.play(tracks, index) })
                        }
                    }
                } else {
                    TrackCarousel(tracks) { index -> player.play(tracks, index) }
                }
            }
        }
    }
}

@Composable
private fun TrendingPreview() {
    val discover = LocalAppContainer.current.discover
    val router = LocalRouter.current
    val trending = discover.trending
    // Without an API key the connect prompt already explains what's missing.
    if (trending is LoadState.Failed && trending.error.offersAccountConnection) return
    val preview = when (trending) {
        is LoadState.Loaded -> LoadState.Loaded(trending.value.take(HomeContent.TRENDING_PREVIEW_COUNT))
        else -> trending
    }
    TrackShelf(
        title = "Trending Now",
        subtitle = discover.chartDescription,
        state = preview,
        onRetry = discover::reload,
        actionTitle = "See All",
        action = { router.select(AppTab.Discover) },
    )
}

/** The latest songs played on this device; hidden until there are some. */
@Composable
private fun JumpBackInShelf() {
    val recents = LocalAppContainer.current.recents
    val player = LocalPlayer.current
    val tracks = recents.plays.take(HomeContent.RECENTS_LIMIT).map { it.track }
    if (tracks.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.medium)) {
        SectionHeader("Jump Back In", Modifier.padding(horizontal = Spacing.large))
        TrackCarousel(tracks) { index -> player.play(tracks, index) }
    }
}

@Composable
private fun PlaylistsShelf() {
    val container = LocalAppContainer.current
    val router = LocalRouter.current
    when (val state = container.library.playlists) {
        LoadState.Idle, LoadState.Loading -> Column(verticalArrangement = Arrangement.spacedBy(Spacing.medium)) {
            SectionHeader("Your Playlists", Modifier.padding(horizontal = Spacing.large))
            ShelfLoading()
        }
        is LoadState.Failed -> Column(
            modifier = Modifier.padding(horizontal = Spacing.large),
            verticalArrangement = Arrangement.spacedBy(Spacing.medium),
        ) {
            SectionHeader("Your Playlists")
            InlineError(state.error) { container.home.load(force = true) }
        }
        is LoadState.Loaded -> if (state.value.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.medium)) {
                SectionHeader(
                    "Your Playlists",
                    Modifier.padding(start = Spacing.large, end = Spacing.small),
                    actionTitle = "See All",
                    onAction = { router.select(AppTab.Playlists) },
                )
                LazyRow(
                    contentPadding = PaddingValues(horizontal = Spacing.large),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.large),
                ) {
                    items(state.value, key = { it.id }) { playlist ->
                        PlaylistCard(playlist) { router.push(Route.PlaylistDetail(playlist)) }
                    }
                }
            }
        }
    }
}

@Composable
private fun RecentlyAddedShelf(home: HomeModel) {
    val router = LocalRouter.current
    val player = LocalPlayer.current
    when (val state = home.recentlyAdded) {
        LoadState.Idle, LoadState.Loading -> Column(verticalArrangement = Arrangement.spacedBy(Spacing.medium)) {
            SectionHeader("Recently Added", Modifier.padding(horizontal = Spacing.large))
            ShelfLoading()
        }
        // A playlist problem already shows on the playlists shelf, so this one just stays hidden.
        is LoadState.Failed -> Unit
        is LoadState.Loaded -> if (state.value.isNotEmpty()) {
            val tracks = state.value.map { it.track }
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.medium)) {
                SectionHeader(
                    "Recently Added",
                    Modifier.padding(start = Spacing.large, end = Spacing.small),
                    subtitle = "Songs you added to your playlists",
                    actionTitle = "See All",
                    onAction = { router.push(Route.RecentlyAdded(state.value)) },
                )
                TrackCarousel(tracks) { index -> player.play(tracks, index) }
            }
        }
    }
}

/** Every song recently added to the user's playlists, from Recently Added's See All. */
@Composable
fun RecentlyAddedScreen(entries: List<AddedTrack>) {
    val player = LocalPlayer.current
    val tracks = entries.map { it.track }
    SubPage("Recently Added") {
        LazyColumn {
            itemsIndexed(tracks, key = { index, track -> "$index#${track.id}" }) { index, track ->
                TrackRow(track, isCurrent = track.isSameSong(player.currentTrack), onClick = { player.play(tracks, index) })
            }
        }
    }
}
