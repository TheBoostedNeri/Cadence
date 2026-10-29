package com.nerijus.cadence.app

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.runtime.staticCompositionLocalOf
import com.nerijus.cadence.catalog.MusicGenre
import com.nerijus.cadence.model.AddedTrack
import com.nerijus.cadence.model.Artist
import com.nerijus.cadence.model.Playlist
import com.nerijus.cadence.model.Track

/** A page opened inside a tab. */
sealed interface Route {
    /** The album a song is from. */
    data class AlbumOf(val track: Track) : Route
    /** An album by its catalog ID, and the song its artist was opened from. */
    data class CatalogAlbum(val id: String, val openedFrom: Track) : Route
    data class ArtistOf(val track: Track) : Route
    data class ArtistSongs(val artist: Artist, val openedFrom: Track) : Route
    data class PlaylistDetail(val playlist: Playlist) : Route
    data class Genre(val genre: MusicGenre) : Route
    data object TrendingChart : Route
    data class RecentlyAdded(val entries: List<AddedTrack>) : Route
}

/** A page on a tab's stack. The key keeps its saved state, like scroll position, apart from
 *  other pages of the same kind, and what it loaded stays with it while it's on the stack. */
class RouteEntry(val key: Int, val route: Route) {
    val retained = mutableMapOf<String, Any>()
}

/** The page being composed, or null on a tab's first page. */
val LocalRouteEntry = staticCompositionLocalOf<RouteEntry?> { null }

/** App-wide navigation: the selected tab, each tab's stack of pages, and what's shown over them. */
class Router {
    var selectedTab by mutableStateOf(AppTab.Home)
        private set
    var isSettingsPresented by mutableStateOf(false)
    /** Songs waiting for the "Add to Playlist" sheet: one from a song's menu, or several picked
     *  with Select. */
    var pendingPlaylistAddition by mutableStateOf<List<Track>?>(null)

    private val stacks = AppTab.entries.associateWith { mutableStateListOf<RouteEntry>() }
    private var nextKey = 0

    fun stack(tab: AppTab): SnapshotStateList<RouteEntry> = stacks.getValue(tab)

    /** Tapping the tab you're on goes back to its first page, as on iPhone. */
    fun select(tab: AppTab) {
        if (tab == selectedTab) stack(tab).clear() else selectedTab = tab
    }

    fun push(route: Route) {
        stack(selectedTab).add(RouteEntry(nextKey++, route))
    }

    fun pop(tab: AppTab = selectedTab) {
        stack(tab).removeLastOrNull()
    }

    fun addToPlaylist(tracks: List<Track>) {
        if (tracks.isNotEmpty()) pendingPlaylistAddition = tracks
    }

    /** Opens the album `track` is from in the tab on screen. */
    fun showAlbum(track: Track) = push(Route.AlbumOf(track))

    fun showAlbum(id: String, openedFrom: Track) = push(Route.CatalogAlbum(id, openedFrom))

    fun showArtist(track: Track) = push(Route.ArtistOf(track))
}

val LocalRouter = staticCompositionLocalOf<Router> { error("No Router provided") }
