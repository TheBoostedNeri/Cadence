package com.nerijus.cadence.auth

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.net.Uri
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.edit
import androidx.core.net.toUri
import com.nerijus.cadence.config.AppConfig
import com.nerijus.cadence.config.GoogleEndpoint
import com.nerijus.cadence.config.GoogleScope
import com.nerijus.cadence.config.OAuthPolicy
import com.nerijus.cadence.model.AppError
import com.nerijus.cadence.network.FORM_CONTENT_TYPE
import com.nerijus.cadence.network.formEncode
import com.nerijus.cadence.network.httpRequest
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject

/**
 * Google OAuth 2.0 for installed apps: the authorization code flow with PKCE, shown in a Chrome
 * Custom Tab, like the iPhone app's. It uses the iPhone app's OAuth client, so Google sends the
 * result back to that client's reversed ID, which this app claims. Tokens are stored encrypted
 * with a key kept in the Android Keystore.
 */
class GoogleAuthService(context: Context, private val config: AppConfig) {
    private val store = TokenStore(context)
    private var tokens: OAuthTokens? = store.load()
    private val refreshLock = Mutex()
    private var pendingRedirect: CompletableDeferred<Uri?>? = null

    var isSignedIn by mutableStateOf(tokens != null)
        private set

    val isConfigured: Boolean get() = config.googleClientId != null

    // Sign in and out

    suspend fun signIn(activity: Activity) {
        val clientId = config.googleClientId ?: throw AppError.MissingClientId
        val redirectUri = config.googleRedirectUri ?: throw AppError.MissingClientId
        val verifier = Pkce.randomString()
        val state = Pkce.randomString()
        val authorizationUrl = GoogleEndpoint.AUTHORIZE.toUri().buildUpon()
            .appendQueryParameter("client_id", clientId)
            .appendQueryParameter("redirect_uri", redirectUri)
            .appendQueryParameter("response_type", "code")
            .appendQueryParameter("scope", GoogleScope.YOUTUBE)
            .appendQueryParameter("code_challenge", Pkce.challenge(verifier))
            .appendQueryParameter("code_challenge_method", "S256")
            .appendQueryParameter("state", state)
            .build()

        val redirect = CompletableDeferred<Uri?>()
        pendingRedirect = redirect
        val returned = try {
            CustomTabsIntent.Builder().build().launchUrl(activity, authorizationUrl)
            redirect.await()
        } catch (_: ActivityNotFoundException) {
            throw AppError.AuthorizationFailed("No browser is installed to sign in with.")
        } finally {
            pendingRedirect = null
        }
        val callback = returned ?: throw AppError.SignInCancelled

        callback.getQueryParameter("error")?.let { error ->
            throw if (error == "access_denied") AppError.SignInCancelled else AppError.AuthorizationFailed(error)
        }
        val code = callback.getQueryParameter("code")
        if (callback.getQueryParameter("state") != state || code == null) {
            throw AppError.AuthorizationFailed("The sign-in response couldn't be verified.")
        }
        val response = requestToken(
            mapOf(
                "grant_type" to "authorization_code",
                "code" to code,
                "client_id" to clientId,
                "redirect_uri" to redirectUri,
                "code_verifier" to verifier,
            ),
        )
        val refreshToken = response.optString("refresh_token").ifEmpty { null }
            ?: throw AppError.AuthorizationFailed("Google didn't grant offline access.")
        save(OAuthTokens.from(response, refreshToken))
    }

    /** Google sent the browser back to the app. Returns whether this was the sign-in's redirect. */
    fun handleRedirect(uri: Uri): Boolean {
        if (uri.scheme != config.googleRedirectScheme) return false
        pendingRedirect?.complete(uri)
        return true
    }

    /** The app came back on screen. If sign-in is still waiting, the browser was closed. */
    fun handleAppResumed() {
        pendingRedirect?.complete(null)
    }

    suspend fun signOut() {
        val refreshToken = tokens?.refreshToken
        clearSession()
        refreshToken ?: return
        // Best effort: revoking also removes the app from the user's Google account permissions.
        runCatching {
            httpRequest(
                GoogleEndpoint.REVOKE,
                method = "POST",
                body = formEncode(mapOf("token" to refreshToken)),
                contentType = FORM_CONTENT_TYPE,
            )
        }
    }

    // Tokens

    /** A current access token, refreshing it if needed, or null when no account is connected. */
    suspend fun validAccessToken(): String? {
        val current = tokens ?: return null
        if (current.expiresAtMillis > System.currentTimeMillis()) return current.accessToken
        return refreshedTokens(current).accessToken
    }

    suspend fun refreshAccessToken() {
        tokens?.let { refreshedTokens(it) }
    }

    /** One refresh at a time; requests that waited use the token it got. */
    private suspend fun refreshedTokens(stale: OAuthTokens): OAuthTokens = refreshLock.withLock {
        val current = tokens ?: throw AppError.SignInRequired
        if (current !== stale && current.expiresAtMillis > System.currentTimeMillis()) return current
        val clientId = config.googleClientId ?: throw AppError.SignInRequired
        try {
            val response = requestToken(
                mapOf(
                    "grant_type" to "refresh_token",
                    "refresh_token" to current.refreshToken,
                    "client_id" to clientId,
                ),
            )
            val refreshToken = response.optString("refresh_token").ifEmpty { current.refreshToken }
            OAuthTokens.from(response, refreshToken).also(::save)
        } catch (error: AppError.SessionExpired) {
            clearSession()
            throw error
        }
    }

    private suspend fun requestToken(parameters: Map<String, String>): JSONObject {
        val response = httpRequest(
            GoogleEndpoint.TOKEN,
            method = "POST",
            body = formEncode(parameters),
            contentType = FORM_CONTENT_TYPE,
        )
        val json = runCatching { JSONObject(response.body) }.getOrNull()
        if (!response.isSuccess) {
            if (json?.optString("error") == "invalid_grant") throw AppError.SessionExpired
            throw AppError.AuthorizationFailed(
                json?.optString("error_description")?.ifEmpty { null }
                    ?: json?.optString("error")?.ifEmpty { null }
                    ?: "Google returned status ${response.statusCode}.",
            )
        }
        return json ?: throw AppError.Decoding
    }

    private fun save(newTokens: OAuthTokens) {
        tokens = newTokens
        isSignedIn = true
        // If storing fails the session still works until the app quits.
        runCatching { store.save(newTokens) }
    }

    private fun clearSession() {
        tokens = null
        isSignedIn = false
        store.clear()
    }
}

private class OAuthTokens(val accessToken: String, val refreshToken: String, val expiresAtMillis: Long) {
    fun toJson(): String = JSONObject()
        .put("accessToken", accessToken)
        .put("refreshToken", refreshToken)
        .put("expiresAtMillis", expiresAtMillis)
        .toString()

    companion object {
        private const val MILLIS_PER_SECOND = 1_000L

        fun from(response: JSONObject, refreshToken: String) = OAuthTokens(
            accessToken = response.getString("access_token"),
            refreshToken = refreshToken,
            expiresAtMillis = System.currentTimeMillis() +
                response.optLong("expires_in") * MILLIS_PER_SECOND - OAuthPolicy.EXPIRY_LEEWAY_MILLIS,
        )

        fun fromJson(json: String): OAuthTokens? = runCatching {
            val stored = JSONObject(json)
            OAuthTokens(stored.getString("accessToken"), stored.getString("refreshToken"), stored.getLong("expiresAtMillis"))
        }.getOrNull()
    }
}

/** Keeps the tokens encrypted with AES-GCM under a key that never leaves the Android Keystore. */
private class TokenStore(context: Context) {
    private val preferences = context.getSharedPreferences(STORE_NAME, Context.MODE_PRIVATE)

    fun load(): OAuthTokens? = runCatching {
        val stored = preferences.getString(TOKENS_KEY, null) ?: return null
        val bytes = Base64.decode(stored, Base64.NO_WRAP)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, bytes, 0, IV_BYTES))
        OAuthTokens.fromJson(String(cipher.doFinal(bytes, IV_BYTES, bytes.size - IV_BYTES)))
    }.getOrNull()

    fun save(tokens: OAuthTokens) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val encrypted = cipher.iv + cipher.doFinal(tokens.toJson().toByteArray())
        preferences.edit { putString(TOKENS_KEY, Base64.encodeToString(encrypted, Base64.NO_WRAP)) }
    }

    fun clear() {
        preferences.edit { remove(TOKENS_KEY) }
    }

    private fun key(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val STORE_NAME = "google_auth"
        const val TOKENS_KEY = "google.oauth.tokens"
        const val KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "cadence.google.oauth"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
        const val TAG_BITS = 128
    }
}

/** Proof Key for Code Exchange (RFC 7636). */
private object Pkce {
    private const val RANDOM_BYTES = 32
    private const val URL_SAFE = Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP

    fun randomString(): String {
        val bytes = ByteArray(RANDOM_BYTES).also(SecureRandom()::nextBytes)
        return Base64.encodeToString(bytes, URL_SAFE)
    }

    fun challenge(verifier: String): String =
        Base64.encodeToString(MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray()), URL_SAFE)
}
