package com.nerijus.cadence.features.home

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nerijus.cadence.library.LibraryStore
import com.nerijus.cadence.model.AddedTrack
import com.nerijus.cadence.model.AppError
import com.nerijus.cadence.model.LoadState
import com.nerijus.cadence.model.Playlist
import com.nerijus.cadence.model.Track
import com.nerijus.cadence.network.YouTubeApiClient
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch

/** Home's personal shelves. Each loads and fails on its own, so one problem never blanks the
 *  whole screen. */
class HomeModel(private val api: YouTubeApiClient, private val library: LibraryStore, private val scope: CoroutineScope) {
    var liked by mutableStateOf<LoadState<List<Track>>>(LoadState.Idle)
        private set
    var subscriptionUploads by mutableStateOf<LoadState<List<Track>>>(LoadState.Idle)
        private set
    var recentlyAdded by mutableStateOf<LoadState<List<AddedTrack>>>(LoadState.Idle)
        private set
    var firstName by mutableStateOf<String?>(null)
        private set
    var isRefreshing by mutableStateOf(false)
        private set
    /** A refresh failure while shelves are already on screen. */
    var refreshError by mutableStateOf<AppError?>(null)

    private var job: Job? = null
    private var hasLoaded = false

    /** Whether every personal shelf has finished loading with nothing in it. */
    val hasNoPersonalContent: Boolean
        get() = liked.isEmptyList() && subscriptionUploads.isEmptyList() && recentlyAdded.isEmptyList() &&
            (library.playlists as? LoadState.Loaded)?.value?.isEmpty() == true

    fun loadIfNeeded() {
        if (!hasLoaded) load(force = false)
    }

    fun load(force: Boolean) {
        hasLoaded = true
        job?.cancel()
        isRefreshing = force
        job = scope.launch {
            try {
                listOf(
                    async { refresh({ liked }, { liked = it }, force) { api.likedMusic() } },
                    async { refresh({ subscriptionUploads }, { subscriptionUploads = it }, force) { api.newFromSubscriptions() } },
                    async { if (force || firstName == null) firstName = api.profileFirstName() },
                    // Recently Added reads the playlists, so it waits for them.
                    async {
                        if (force || library.playlists !is LoadState.Loaded) library.loadPlaylists()
                        val playlists: List<Playlist> = (library.playlists as? LoadState.Loaded)?.value.orEmpty()
                        if (playlists.isEmpty()) {
                            recentlyAdded = LoadState.Loaded(emptyList())
                        } else {
                            refresh({ recentlyAdded }, { recentlyAdded = it }, force) { api.recentlyAdded(playlists) }
                        }
                    },
                ).awaitAll()
            } finally {
                isRefreshing = false
            }
        }
    }

    fun reset() {
        job?.cancel()
        hasLoaded = false
        liked = LoadState.Idle
        subscriptionUploads = LoadState.Idle
        recentlyAdded = LoadState.Idle
        firstName = null
    }

    /** Loads a shelf, leaving what's shown in place while it refreshes. */
    private suspend fun <T> refresh(current: () -> LoadState<T>, set: (LoadState<T>) -> Unit, force: Boolean, load: suspend () -> T) {
        val hasContent = current() is LoadState.Loaded
        if (hasContent && !force) return
        if (!hasContent) set(LoadState.Loading)
        try {
            set(LoadState.Loaded(load()))
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            if (hasContent) refreshError = AppError.from(error) else set(LoadState.Failed(AppError.from(error)))
        }
    }

    private fun <T> LoadState<List<T>>.isEmptyList() = (this as? LoadState.Loaded)?.value?.isEmpty() == true
}
