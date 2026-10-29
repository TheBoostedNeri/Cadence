package com.nerijus.cadence.app

import android.app.Activity
import android.content.Context
import androidx.compose.runtime.staticCompositionLocalOf
import com.nerijus.cadence.auth.GoogleAuthService
import com.nerijus.cadence.catalog.CatalogBrowser
import com.nerijus.cadence.catalog.SongVersions
import com.nerijus.cadence.catalog.YouTubeMatcher
import com.nerijus.cadence.config.AppConfig
import com.nerijus.cadence.features.discover.DiscoverModel
import com.nerijus.cadence.features.home.HomeModel
import com.nerijus.cadence.features.search.SearchModel
import com.nerijus.cadence.images.ImageLoader
import com.nerijus.cadence.library.LibraryStore
import com.nerijus.cadence.library.RecentsStore
import com.nerijus.cadence.library.YouTubeLikes
import com.nerijus.cadence.lyrics.LyricsService
import com.nerijus.cadence.network.YouTubeApiClient
import com.nerijus.cadence.playback.BackgroundPlayback
import com.nerijus.cadence.playback.PlayerController
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel

/** The app's long-lived services and screen models, made once per window. Screens keep their
 *  results while you switch tabs, so coming back doesn't spend quota again. */
class AppContainer(context: Context) {
    val scope = MainScope()
    val config = AppConfig.load()
    val settings = AppSettings(context)
    val auth = GoogleAuthService(context.applicationContext, config)
    val api = YouTubeApiClient(config, auth)
    val imageLoader = ImageLoader(context.applicationContext)
    val catalog = CatalogBrowser(config)
    private val matcher = YouTubeMatcher(context.applicationContext, api)
    private val versions = SongVersions(context.applicationContext, api)
    val library = LibraryStore(api, matcher)
    val likes = YouTubeLikes(api) { auth.isSignedIn }
    val recents = RecentsStore(context.applicationContext, scope)
    val lyrics = LyricsService(context.applicationContext)
    val router = Router()
    val player = PlayerController(context, config, settings).apply {
        onTrackStarted = recents::record
        matchYouTubeVideo = matcher::match
        findOtherVersion = versions::otherVersion
        findAutoplayTracks = catalog::autoplayTracks
    }
    val backgroundPlayback = BackgroundPlayback(context.applicationContext, player, settings, imageLoader, scope)
    val discover = DiscoverModel(api, scope)
    val search = SearchModel(api, scope)
    val home = HomeModel(api, library, scope)

    /** Connects a YouTube account in a browser tab over `activity`. */
    suspend fun signIn(activity: Activity) {
        auth.signIn(activity)
        library.reset()
    }

    suspend fun signOut() {
        auth.signOut()
        library.reset()
        home.reset()
    }

    fun release() {
        backgroundPlayback.release()
        scope.cancel()
        player.release()
    }
}

val LocalAppContainer = staticCompositionLocalOf<AppContainer> { error("No AppContainer provided") }
val LocalImageLoader = staticCompositionLocalOf<ImageLoader> { error("No ImageLoader provided") }
val LocalPlayer = staticCompositionLocalOf<PlayerController> { error("No PlayerController provided") }
