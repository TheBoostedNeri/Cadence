package com.nerijus.cadence.designsystem.components

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.nerijus.cadence.app.LocalAppContainer
import com.nerijus.cadence.app.LocalRouteEntry
import com.nerijus.cadence.model.AppError
import com.nerijus.cadence.model.LoadState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/** Loads something for a screen and keeps it, with a refresh that leaves what's shown in place
 *  and reports its failure separately. */
class Loader<T>(private val scope: CoroutineScope, private val load: suspend () -> T) {
    var state by mutableStateOf<LoadState<T>>(LoadState.Idle)
        private set
    var isRefreshing by mutableStateOf(false)
        private set
    /** A refresh failure while content is already on screen. */
    var refreshError by mutableStateOf<AppError?>(null)

    private var job: Job? = null

    val value: T? get() = (state as? LoadState.Loaded)?.value

    fun loadIfNeeded() {
        if (state == LoadState.Idle) reload()
    }

    fun reload() {
        job?.cancel()
        val hasContent = state is LoadState.Loaded
        if (hasContent) isRefreshing = true else state = LoadState.Loading
        job = scope.launch {
            try {
                state = LoadState.Loaded(load())
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (hasContent) refreshError = AppError.from(error) else state = LoadState.Failed(AppError.from(error))
            } finally {
                isRefreshing = false
            }
        }
    }

    /** Shows a change made here, like a removed song, without loading again. */
    fun replace(value: T) {
        state = LoadState.Loaded(value)
    }
}

/** A loader that stays with the page it's on, so going back to the page doesn't load it again. */
@Composable
fun <T> rememberLoader(name: String, load: suspend () -> T): Loader<T> {
    val entry = LocalRouteEntry.current
    val scope = LocalAppContainer.current.scope
    val loader = remember(entry, name) {
        @Suppress("UNCHECKED_CAST")
        (entry?.retained?.getOrPut(name) { Loader(scope, load) } ?: Loader(scope, load)) as Loader<T>
    }
    LaunchedEffect(loader) { loader.loadIfNeeded() }
    ErrorDialog(loader.refreshError) { loader.refreshError = null }
    return loader
}

/** Pull down to refresh, like the iPhone app's refreshable lists. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun Refreshable(isRefreshing: Boolean, onRefresh: () -> Unit, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    PullToRefreshBox(isRefreshing = isRefreshing, onRefresh = onRefresh, modifier = modifier) { content() }
}

/** An alert for something that went wrong after the screen loaded, like a failed edit. */
@Composable
fun ErrorDialog(error: AppError?, onDismiss: () -> Unit) {
    error ?: return
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = { TextButton(onClick = onDismiss) { Text("OK") } },
        title = { Text(error.title) },
        text = { Text(error.message) },
    )
}
