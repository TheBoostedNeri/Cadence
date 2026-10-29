package com.nerijus.cadence.features.discover

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nerijus.cadence.model.AppError
import com.nerijus.cadence.model.LoadState
import com.nerijus.cadence.model.Track
import com.nerijus.cadence.network.YouTubeApiClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/** Discover's Trending chart, loaded once and kept while the app runs. */
class DiscoverModel(private val api: YouTubeApiClient, private val scope: CoroutineScope) {
    var trending by mutableStateOf<LoadState<List<Track>>>(LoadState.Idle)
        private set
    var isRefreshing by mutableStateOf(false)
        private set

    val chartDescription: String get() = api.chartDescription

    private var job: Job? = null

    fun loadIfNeeded() {
        if (trending == LoadState.Idle) reload()
    }

    /** Loads the chart, leaving the one shown in place while it refreshes. */
    fun reload() {
        job?.cancel()
        val hasChart = trending is LoadState.Loaded
        if (hasChart) isRefreshing = true else trending = LoadState.Loading
        job = scope.launch {
            try {
                trending = LoadState.Loaded(api.trendingMusic())
            } catch (error: Exception) {
                val failure = AppError.from(error)
                if (!hasChart) trending = LoadState.Failed(failure)
            } finally {
                isRefreshing = false
            }
        }
    }
}
