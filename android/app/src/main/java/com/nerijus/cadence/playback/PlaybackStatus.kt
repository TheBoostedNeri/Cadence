package com.nerijus.cadence.playback

import com.nerijus.cadence.model.AppError

sealed interface PlaybackStatus {
    data object Idle : PlaybackStatus
    data object Loading : PlaybackStatus
    data object Buffering : PlaybackStatus
    data object Playing : PlaybackStatus
    data object Paused : PlaybackStatus
    data object Ended : PlaybackStatus
    data class Failed(val error: AppError) : PlaybackStatus

    /** Playing or about to: the button shows Pause. */
    val isActive: Boolean get() = this == Loading || this == Buffering || this == Playing

    /** Waiting on YouTube: a spinner shows over the video. */
    val isWaiting: Boolean get() = this == Loading || this == Buffering
}
