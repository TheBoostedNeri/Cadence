package com.nerijus.cadence.model

/** Where a screen's content is in loading. */
sealed interface LoadState<out T> {
    data object Idle : LoadState<Nothing>
    data object Loading : LoadState<Nothing>
    data class Loaded<T>(val value: T) : LoadState<T>
    data class Failed(val error: AppError) : LoadState<Nothing>
}
