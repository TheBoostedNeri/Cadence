package com.nerijus.cadence

import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.addCallback
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import com.nerijus.cadence.app.AppContainer
import com.nerijus.cadence.app.CadenceApp
import com.nerijus.cadence.app.LocalAppContainer
import com.nerijus.cadence.app.LocalImageLoader
import com.nerijus.cadence.app.LocalPlayer
import com.nerijus.cadence.designsystem.CadenceTheme

class MainActivity : ComponentActivity() {
    // Rotation and resizing don't recreate the activity (see the manifest), so the player and
    // the song keep going.
    private lateinit var container: AppContainer

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        container = AppContainer(this)
        // Back on a tab's first page leaves the app running, as Android 12 and later do, so
        // background play carries on. Pages' own Back handlers, added later, come first.
        onBackPressedDispatcher.addCallback(this) { moveTaskToBack(true) }
        // Content runs under the status and navigation bars, like the iPhone app's full-bleed pages.
        enableEdgeToEdge()
        setContent {
            CompositionLocalProvider(
                LocalAppContainer provides container,
                LocalImageLoader provides container.imageLoader,
                LocalPlayer provides container.player,
            ) {
                CadenceTheme {
                    CadenceApp()
                }
            }
        }
    }

    /** Google's sign-in comes back here, through the redirect this activity claims. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.data?.let(container.auth::handleRedirect)
    }

    override fun onResume() {
        super.onResume()
        container.auth.handleAppResumed()
    }

    /** Switching between light and dark doesn't recreate the activity either, so the system bar
     *  icons are matched to the new appearance here. */
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        enableEdgeToEdge()
    }

    override fun onStart() {
        super.onStart()
        container.backgroundPlayback.isAppVisible = true
    }

    /** YouTube's player may not play while the app is off screen, unless background play is on. */
    override fun onStop() {
        super.onStop()
        container.backgroundPlayback.isAppVisible = false
        container.player.handleAppBackgrounded()
    }

    override fun onDestroy() {
        container.release()
        super.onDestroy()
    }
}
