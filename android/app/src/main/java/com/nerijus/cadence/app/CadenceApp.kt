package com.nerijus.cadence.app

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.saveable.SaveableStateHolder
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.nerijus.cadence.designsystem.Layout
import com.nerijus.cadence.designsystem.Motion
import com.nerijus.cadence.features.catalog.AlbumScreen
import com.nerijus.cadence.features.catalog.ArtistScreen
import com.nerijus.cadence.features.catalog.ArtistSongsScreen
import com.nerijus.cadence.features.discover.DiscoverScreen
import com.nerijus.cadence.features.discover.GenreScreen
import com.nerijus.cadence.features.discover.TrendingChartScreen
import com.nerijus.cadence.features.home.HomeScreen
import com.nerijus.cadence.features.home.RecentlyAddedScreen
import com.nerijus.cadence.features.onboarding.OnboardingScreen
import com.nerijus.cadence.features.player.MiniPlayer
import com.nerijus.cadence.features.player.NowPlayingScreen
import com.nerijus.cadence.features.playlists.AddToPlaylistSheet
import com.nerijus.cadence.features.playlists.PlaylistDetailScreen
import com.nerijus.cadence.features.playlists.PlaylistsScreen
import com.nerijus.cadence.features.recents.RecentsScreen
import com.nerijus.cadence.features.search.SearchScreen
import com.nerijus.cadence.features.settings.SettingsScreen
import com.nerijus.cadence.playback.YouTubePlayerHost

/** The tabs and the mini player, with Now Playing sliding up over them. Phones get a bottom bar;
 *  tablets and wide windows get a side rail, like the iPad app's sidebar. */
@Composable
fun CadenceApp() {
    val container = LocalAppContainer.current
    val router = container.router
    val player = container.player
    val tabStates = rememberSaveableStateHolder()

    CompositionLocalProvider(LocalRouter provides router) {
        Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
            NavigationSuiteScaffold(
                navigationSuiteItems = {
                    AppTab.entries.forEach { tab ->
                        item(
                            selected = tab == router.selectedTab,
                            onClick = { router.select(tab) },
                            icon = { Icon(tab.icon, contentDescription = null) },
                            label = { Text(tab.title) },
                        )
                    }
                },
            ) {
                Column(Modifier.fillMaxSize()) {
                    Box(Modifier.weight(1f)) {
                        // Each tab keeps its pages and scroll positions while another is shown.
                        tabStates.SaveableStateProvider(router.selectedTab.name) {
                            TabStack(router.selectedTab)
                        }
                    }
                    MiniPlayer()
                }
            }

            // The player waits here, tiny, unless Now Playing is open on a music video: songs show
            // their artwork there instead.
            if (!player.showsVideoInNowPlaying) {
                YouTubePlayerHost(
                    player.webView,
                    Modifier
                        .align(Alignment.BottomStart)
                        .size(Layout.hiddenPlayerSide),
                )
            }

            AnimatedVisibility(
                visible = player.isNowPlayingPresented,
                enter = slideInVertically(tween(Motion.NOW_PLAYING_MILLIS)) { it },
                exit = slideOutVertically(tween(Motion.NOW_PLAYING_MILLIS)) { it },
            ) {
                NowPlayingScreen(player)
            }

            AnimatedVisibility(
                visible = router.isSettingsPresented,
                enter = slideInVertically(tween(Motion.NOW_PLAYING_MILLIS)) { it },
                exit = slideOutVertically(tween(Motion.NOW_PLAYING_MILLIS)) { it },
            ) {
                Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) { SettingsScreen() }
            }

            if (!container.settings.hasCompletedOnboarding) OnboardingScreen()
        }

        router.pendingPlaylistAddition?.let { tracks ->
            AddToPlaylistSheet(tracks, onDismiss = { router.pendingPlaylistAddition = null })
        }
    }
}

/** A tab's first page and the pages opened on top of it, sliding in and out like a navigation
 *  stack. Back goes to the page before. */
@Composable
private fun TabStack(tab: AppTab) {
    val router = LocalRouter.current
    val stack = router.stack(tab)
    val pageStates = rememberSaveableStateHolder()
    BackHandler(enabled = stack.isNotEmpty()) { router.pop(tab) }

    AnimatedContent(
        targetState = stack.lastOrNull(),
        transitionSpec = {
            val isForward = (targetState?.key ?: -1) > (initialState?.key ?: -1)
            if (isForward) {
                slideInHorizontally { it } togetherWith slideOutHorizontally { -it / PARALLAX } + fadeOut()
            } else {
                slideInHorizontally { -it / PARALLAX } + fadeIn() togetherWith slideOutHorizontally { it }
            }
        },
        label = "pages",
    ) { entry ->
        Page(entry, tab, pageStates)
    }
}

/** How far the page underneath moves, as a fraction of the width, while another slides over it. */
private const val PARALLAX = 4

@Composable
private fun Page(entry: RouteEntry?, tab: AppTab, pageStates: SaveableStateHolder) {
    pageStates.SaveableStateProvider(entry?.key ?: -1) {
        CompositionLocalProvider(LocalRouteEntry provides entry) {
            Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
                when (val route = entry?.route) {
                    null -> when (tab) {
                        AppTab.Home -> HomeScreen()
                        AppTab.Discover -> DiscoverScreen()
                        AppTab.Playlists -> PlaylistsScreen()
                        AppTab.Recents -> RecentsScreen()
                        AppTab.Search -> SearchScreen()
                    }
                    is Route.AlbumOf -> AlbumScreen(route.track)
                    is Route.CatalogAlbum -> AlbumScreen(route.openedFrom, albumId = route.id)
                    is Route.ArtistOf -> ArtistScreen(route.track)
                    is Route.ArtistSongs -> ArtistSongsScreen(route.artist)
                    is Route.PlaylistDetail -> PlaylistDetailScreen(route.playlist)
                    is Route.Genre -> GenreScreen(route.genre)
                    Route.TrendingChart -> TrendingChartScreen()
                    is Route.RecentlyAdded -> RecentlyAddedScreen(route.entries)
                }
            }
        }
    }
}
