package com.nerijus.cadence.features.search

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.nerijus.cadence.config.SearchPolicy
import com.nerijus.cadence.model.AppError
import com.nerijus.cadence.model.LoadState
import com.nerijus.cadence.model.Track
import com.nerijus.cadence.network.YouTubeApiClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Live search: results update once typing pauses, since every search costs 100 quota units. */
class SearchModel(private val api: YouTubeApiClient, private val scope: CoroutineScope) {
    var query by mutableStateOf("")
        private set
    var results by mutableStateOf<LoadState<List<Track>>>(LoadState.Idle)
        private set

    private var job: Job? = null
    /** The query being searched for or answered, so pressing Search again doesn't search again. */
    private var searchedQuery: String? = null

    fun updateQuery(newQuery: String) {
        query = newQuery
        schedule(waitForTyping = true)
    }

    /** Searches straight away, from the keyboard's Search key. */
    fun submit() {
        schedule(waitForTyping = false)
    }

    fun retry() {
        searchedQuery = null
        schedule(waitForTyping = false)
    }

    private fun schedule(waitForTyping: Boolean) {
        val trimmed = query.trim()
        val isAnswered = results is LoadState.Loaded || job?.isActive == true
        if (trimmed == searchedQuery && isAnswered) return
        job?.cancel()
        searchedQuery = null
        if (trimmed.length < SearchPolicy.MINIMUM_QUERY_LENGTH) {
            results = LoadState.Idle
            return
        }
        searchedQuery = trimmed
        job = scope.launch {
            if (waitForTyping) delay(SearchPolicy.typingPause)
            results = LoadState.Loading
            results = try {
                LoadState.Loaded(api.search(trimmed))
            } catch (error: Exception) {
                searchedQuery = null
                LoadState.Failed(AppError.from(error))
            }
        }
    }
}
