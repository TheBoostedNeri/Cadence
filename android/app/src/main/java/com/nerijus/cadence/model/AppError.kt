package com.nerijus.cadence.model

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.HourglassEmpty
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.QuestionMark
import androidx.compose.material.icons.filled.SignalWifiConnectedNoInternet4
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.MusicOff
import androidx.compose.ui.graphics.vector.ImageVector
import com.nerijus.cadence.config.YouTubePlayerErrorCode
import kotlinx.coroutines.CancellationException
import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import org.json.JSONException

enum class PlaybackFailure {
    InvalidVideo,
    Unavailable,
    EmbeddingDisabled,
    PlayerConfiguration,
    PlayerError,
    /** A catalog song with no YouTube video to play. */
    NoYouTubeMatch,
    /** A song with no music video to switch to. */
    NoMusicVideo,
    /** A music video with no audio upload to switch to. */
    NoSongVersion;

    companion object {
        /** Maps IFrame Player API `onError` codes. */
        fun fromYouTubeErrorCode(code: Int) = when (code) {
            YouTubePlayerErrorCode.INVALID_PARAMETER -> InvalidVideo
            YouTubePlayerErrorCode.NOT_FOUND -> Unavailable
            YouTubePlayerErrorCode.EMBEDDING_NOT_ALLOWED,
            YouTubePlayerErrorCode.EMBEDDING_NOT_ALLOWED_ALTERNATE -> EmbeddingDisabled
            YouTubePlayerErrorCode.MISSING_CLIENT_IDENTITY -> PlayerConfiguration
            else -> PlayerError
        }
    }
}

/** Every failure the UI can present, with the same copy as the iPhone app. */
sealed class AppError : Exception() {
    data object MissingApiKey : AppError()
    data object MissingClientId : AppError()
    data object SignInRequired : AppError()
    data object SignInCancelled : AppError()
    data object SessionExpired : AppError()
    data object ChannelRequired : AppError()
    data class AuthorizationFailed(val detail: String) : AppError()
    data object InvalidApiKey : AppError()
    data object ApiNotEnabled : AppError()
    data object Offline : AppError()
    data class Network(val detail: String) : AppError()
    data object QuotaExceeded : AppError()
    data class Forbidden(val detail: String?) : AppError()
    data object NotFound : AppError()
    data class Server(val statusCode: Int, val detail: String?) : AppError()
    data object Decoding : AppError()
    data class Playback(val failure: PlaybackFailure, val code: Int? = null) : AppError()
    data class LyricsService(val statusCode: Int) : AppError()

    val title: String
        get() = when (this) {
            MissingApiKey -> "Connect to Start Listening"
            MissingClientId -> "Account Connection Not Set Up"
            SignInRequired -> "Connect Your Account"
            SignInCancelled -> "Sign-In Cancelled"
            SessionExpired -> "Session Expired"
            ChannelRequired -> "YouTube Channel Needed"
            is AuthorizationFailed -> "Couldn't Connect"
            InvalidApiKey -> "Invalid API Key"
            ApiNotEnabled -> "YouTube API Not Enabled"
            Offline -> "You're Offline"
            is Network -> "Connection Problem"
            QuotaExceeded -> "Daily Limit Reached"
            is Forbidden -> "Access Denied"
            NotFound -> "Not Found"
            is Server -> "YouTube Error"
            Decoding -> "Unexpected Response"
            is Playback -> when (failure) {
                PlaybackFailure.EmbeddingDisabled -> "Can't Play Here"
                PlaybackFailure.Unavailable -> "Video Unavailable"
                PlaybackFailure.InvalidVideo -> "Can't Play This Video"
                PlaybackFailure.PlayerConfiguration -> "Player Setup Problem"
                PlaybackFailure.PlayerError -> "Playback Error"
                PlaybackFailure.NoYouTubeMatch -> "Not on YouTube"
                PlaybackFailure.NoMusicVideo -> "No Music Video"
                PlaybackFailure.NoSongVersion -> "No Song Version"
            }
            is LyricsService -> "Lyrics Unavailable"
        }

    override val message: String
        get() = when (this) {
            MissingApiKey -> "Connect your YouTube account, or add a YouTube Data API key (YOUTUBE_API_KEY) to Config/Secrets.xcconfig and build the app again."
            MissingClientId -> "Add the iOS OAuth client ID (GOOGLE_CLIENT_ID) to Config/Secrets.xcconfig to connect a YouTube account."
            SignInRequired -> "Connect your YouTube account to use your playlists."
            SignInCancelled -> "You can connect your account any time from Settings."
            SessionExpired -> "Connect your YouTube account again to continue."
            ChannelRequired -> "This Google account doesn't have a YouTube channel yet. Create one on YouTube to use playlists."
            is AuthorizationFailed -> detail
            InvalidApiKey -> "YouTube rejected the API key. Check YOUTUBE_API_KEY and its iOS app restriction."
            ApiNotEnabled -> "Enable YouTube Data API v3 for your Google Cloud project, then try again."
            Offline -> "Check your internet connection and try again."
            is Network -> detail
            QuotaExceeded -> "The app has used its YouTube API quota for today. Try again tomorrow."
            is Forbidden -> detail ?: "YouTube didn't allow this request."
            NotFound -> "This item no longer exists on YouTube."
            is Server -> detail ?: "YouTube returned an error ($statusCode). Please try again."
            Decoding -> "YouTube sent data this version of the app can't read."
            is Playback -> when (failure) {
                PlaybackFailure.EmbeddingDisabled -> "The owner of this video doesn't allow it to play outside YouTube."
                PlaybackFailure.Unavailable -> "This video was removed or made private."
                PlaybackFailure.InvalidVideo -> "This video can't be loaded."
                PlaybackFailure.PlayerConfiguration -> "YouTube's player didn't accept this app's identity. Check the app ID and try again."
                PlaybackFailure.PlayerError -> "The YouTube player reported error $code."
                PlaybackFailure.NoYouTubeMatch -> "Cadence couldn't find a YouTube video of this song."
                PlaybackFailure.NoMusicVideo -> "Cadence couldn't find a music video of this song on YouTube."
                PlaybackFailure.NoSongVersion -> "Cadence couldn't find this song's audio on YouTube."
            }
            is LyricsService -> "The lyrics service returned an error ($statusCode). Try again later."
        }

    val icon: ImageVector
        get() = when (this) {
            MissingApiKey, SignInRequired, SessionExpired -> Icons.Filled.AccountCircle
            MissingClientId -> Icons.Filled.VpnKey
            SignInCancelled, is AuthorizationFailed -> Icons.Filled.Lock
            ChannelRequired -> Icons.Filled.PersonAdd
            InvalidApiKey, ApiNotEnabled -> Icons.Filled.Build
            is Forbidden -> Icons.Filled.Lock
            Offline -> Icons.Filled.WifiOff
            is Network -> Icons.Filled.SignalWifiConnectedNoInternet4
            QuotaExceeded -> Icons.Filled.HourglassEmpty
            NotFound -> Icons.Filled.QuestionMark
            is Playback -> Icons.Outlined.MusicOff
            is LyricsService -> Icons.Outlined.ChatBubbleOutline
            is Server, Decoding -> Icons.Filled.Warning
        }

    val isRetryable: Boolean
        get() = when (this) {
            Offline, is Network, is Server, Decoding, ApiNotEnabled, is LyricsService, is AuthorizationFailed -> true
            is Playback -> failure == PlaybackFailure.PlayerConfiguration || failure == PlaybackFailure.PlayerError
            else -> false
        }

    /** Errors the user resolves by connecting a YouTube account. */
    val offersAccountConnection: Boolean
        get() = this == MissingApiKey || this == SignInRequired || this == SessionExpired

    companion object {
        /** Wraps any failure for display. Cancellation passes through so callers can ignore it. */
        fun from(error: Throwable): AppError = when (error) {
            is CancellationException -> throw error
            is AppError -> error
            is UnknownHostException, is ConnectException -> Offline
            is SocketTimeoutException -> Network("The connection timed out.")
            is JSONException -> Decoding
            is IOException -> Network(error.localizedMessage ?: "The connection failed.")
            else -> Network(error.localizedMessage ?: "Something went wrong.")
        }
    }
}
