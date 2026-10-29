package com.nerijus.cadence.config

import com.nerijus.cadence.BuildConfig
import java.util.Locale

/** Values injected at build time from Config/Base.xcconfig and Config/Secrets.xcconfig, shared with the iPhone app. */
data class AppConfig(
    val youtubeApiKey: String?,
    /** The iPhone app's bundle ID, which the API key is restricted to. */
    val iosBundleIdentifier: String,
    val applicationId: String,
    /** The iPhone app's OAuth client ID, which the Android app signs in with too. */
    val googleClientId: String?,
) {
    /** Google iOS OAuth clients redirect to the reversed client ID,
     *  e.g. `123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc`. */
    val googleRedirectScheme: String? get() = googleClientId?.split(".")?.reversed()?.joinToString(".")

    val googleRedirectUri: String? get() = googleRedirectScheme?.let { "$it:/oauth2redirect" }

    /** Origin the embedded player identifies itself with. YouTube requires embeds to send an
     *  HTTP Referer, so the player page is loaded with a stable URL derived from the app's ID. */
    val playerOrigin: String get() = "https://${applicationId.lowercase()}"

    /** ISO 3166-1 alpha-2 region used for charts. */
    val regionCode: String
        get() {
            val country = Locale.getDefault().country
            return if (country.length == FALLBACK_REGION_CODE.length && country.all(Char::isLetter)) {
                country
            } else {
                FALLBACK_REGION_CODE
            }
        }

    val regionName: String get() = Locale.Builder().setRegion(regionCode).build().displayCountry

    companion object {
        private const val FALLBACK_REGION_CODE = "US"

        fun load() = AppConfig(
            youtubeApiKey = BuildConfig.YOUTUBE_API_KEY.trim().ifEmpty { null },
            iosBundleIdentifier = BuildConfig.IOS_BUNDLE_IDENTIFIER.trim().ifEmpty { BuildConfig.APPLICATION_ID },
            applicationId = BuildConfig.APPLICATION_ID,
            googleClientId = BuildConfig.GOOGLE_CLIENT_ID.trim().ifEmpty { null },
        )
    }
}
