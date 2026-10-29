package com.nerijus.cadence.app

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.edit

/** Preferences kept on this device, shared with the screens as Compose state. */
class AppSettings(context: Context) {
    private val store = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    private var backgroundPlay by mutableStateOf(store.getBoolean(BACKGROUND_PLAY_KEY, false))
    private var onboardingDone by mutableStateOf(store.getBoolean(ONBOARDING_KEY, false))

    /** Experimental and unofficial: keep YouTube playing with Now Playing closed or the app in
     *  the background. Breaks YouTube's API Terms, so it's off unless turned on in Settings. */
    var isBackgroundPlayEnabled: Boolean
        get() = backgroundPlay
        set(enabled) {
            backgroundPlay = enabled
            store.edit { putBoolean(BACKGROUND_PLAY_KEY, enabled) }
        }

    var hasCompletedOnboarding: Boolean
        get() = onboardingDone
        set(done) {
            onboardingDone = done
            store.edit { putBoolean(ONBOARDING_KEY, done) }
        }

    var isAutoplayEnabled: Boolean
        get() = store.getBoolean(AUTOPLAY_KEY, false)
        set(enabled) = store.edit { putBoolean(AUTOPLAY_KEY, enabled) }

    private companion object {
        const val BACKGROUND_PLAY_KEY = "experimental.youtubeBackgroundPlay"
        const val ONBOARDING_KEY = "hasCompletedOnboarding"
        const val AUTOPLAY_KEY = "autoplay"
    }
}
