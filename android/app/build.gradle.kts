import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

/**
 * The iPhone app's build settings: `KEY = value` lines from Config/Base.xcconfig, overridden by the
 * git-ignored Config/Secrets.xcconfig. The Android app shares its YouTube API key and bundle ID.
 */
fun xcconfigValues(): Map<String, String> {
    val configDirectory = rootDir.resolve("../Config")
    return listOf("Base.xcconfig", "Secrets.xcconfig")
        .map(configDirectory::resolve)
        .filter { it.isFile }
        .flatMap { it.readLines() }
        .map { it.substringBefore("//").trim() }
        .filter { "=" in it && !it.startsWith("#") }
        .associate { it.substringBefore("=").trim() to it.substringAfter("=").trim() }
}

val xcconfig = xcconfigValues()

/**
 * Release signing: `KEY=value` lines from the git-ignored android/keystore.properties. Without it,
 * release builds come out unsigned and phones won't install them.
 */
val keystoreProperties = rootDir.resolve("keystore.properties")
    .takeIf { it.isFile }
    ?.let { file -> Properties().apply { file.inputStream().use { load(it) } } }

/** A Kotlin string literal for `buildConfigField`. */
fun quoted(value: String) = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

android {
    namespace = "com.nerijus.cadence"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.nerijus.cadence"
        // Android 10: WebView updates through the Play Store, which YouTube's player relies on.
        minSdk = 29
        targetSdk = 37
        versionCode = 1
        versionName = "0.1"

        // The key is restricted to iOS apps, so requests name the iPhone app's bundle ID, as the
        // Mac app's do. Empty when Config/Secrets.xcconfig doesn't set them.
        buildConfigField("String", "YOUTUBE_API_KEY", quoted(xcconfig["YOUTUBE_API_KEY"].orEmpty()))
        buildConfigField("String", "IOS_BUNDLE_IDENTIFIER", quoted(xcconfig["CADENCE_BUNDLE_IDENTIFIER"].orEmpty()))
        // The iPhone app's OAuth client. Google sends sign-in back to its reversed ID, such as
        // com.googleusercontent.apps.123-abc, which the manifest claims for this app.
        val googleClientId = xcconfig["GOOGLE_CLIENT_ID"].orEmpty()
        buildConfigField("String", "GOOGLE_CLIENT_ID", quoted(googleClientId))
        manifestPlaceholders["googleRedirectScheme"] = googleClientId
            .split(".")
            .reversed()
            .joinToString(".")
            .ifEmpty { "com.nerijus.cadence.oauth" }
    }

    signingConfigs {
        keystoreProperties?.let { properties ->
            create("release") {
                storeFile = file(properties.getProperty("storeFile"))
                storePassword = properties.getProperty("storePassword")
                keyAlias = properties.getProperty("keyAlias")
                keyPassword = properties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.findByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.browser)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material3.navigation.suite)
    implementation(libs.androidx.compose.material.icons.extended)
    debugImplementation(libs.androidx.compose.ui.tooling)
}
