package com.nerijus.cadence.designsystem

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

/** Semantic colors, matching the iPhone and Mac app's Palette and its brand color. */
object Palette {
    /** Assets.xcassets/AccentColor, light and dark. */
    val brandLight = Color(0xFF5B3DF5)
    val brandDark = Color(0xFF7B61FF)
    val onBrand = Color.White
    val backgroundTopLight = Color(0xFFF3F0FF)
    val backgroundTopDark = Color(0xFF17132B)
    val playerBackground = Color.Black
    val onPlayer = Color.White
    /** Discover's genre tiles, in the order of the iPhone app's genreTints. */
    val genreTints = listOf(
        Color(0xFFFF2D55), Color(0xFFFF9500), Color(0xFFAF52DE), Color(0xFF007AFF), Color(0xFF30B0C7),
        Color(0xFFFF3B30), Color(0xFF5856D6), Color(0xFF34C759), Color(0xFF00C7BE), Color(0xFF32ADE6),
        Color(0xFFA2845E),
    )
    val success = Color(0xFF34C759)
    val warning = Color(0xFFFF9500)
}

private val LightColors = lightColorScheme(
    primary = Palette.brandLight,
    onPrimary = Palette.onBrand,
    surface = Color.White,
    background = Color.White,
)

private val DarkColors = darkColorScheme(
    primary = Palette.brandDark,
    onPrimary = Palette.onBrand,
    surface = Color.Black,
    background = Color.Black,
)

/** Cadence's colors and type, following the system's light or dark appearance. */
@Composable
fun CadenceTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = CadenceTypography,
        content = content,
    )
}

/** The soft brand-tinted wash at the top of every page, like the iPhone app's backgroundGradient. */
@Composable
fun backgroundGradient(darkTheme: Boolean = isSystemInDarkTheme()): Brush {
    val top = if (darkTheme) Palette.backgroundTopDark else Palette.backgroundTopLight
    return Brush.verticalGradient(0f to top, 0.5f to MaterialTheme.colorScheme.background)
}
