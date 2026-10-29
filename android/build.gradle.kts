plugins {
    alias(libs.plugins.android.application) apply false
    // Not applied: AGP 9 compiles Kotlin itself. Listing it here picks the Kotlin version it uses.
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.compose) apply false
}
