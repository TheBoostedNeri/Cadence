package com.nerijus.cadence.designsystem

import androidx.compose.material3.Typography
import androidx.compose.ui.text.font.FontWeight

/** Material's type scale, made bolder where the iPhone app uses bold titles. It scales with the
 *  system font size, like Dynamic Type. */
val CadenceTypography = Typography().run {
    copy(
        headlineLarge = headlineLarge.copy(fontWeight = FontWeight.Bold),
        headlineMedium = headlineMedium.copy(fontWeight = FontWeight.Bold),
        titleLarge = titleLarge.copy(fontWeight = FontWeight.SemiBold),
        titleMedium = titleMedium.copy(fontWeight = FontWeight.SemiBold),
    )
}

/** Type for lyrics, matching the iPhone app's. */
object LyricType {
    /** Synced lyrics: large and bold, like Apple Music's. */
    val synced = CadenceTypography.headlineLarge.copy(fontWeight = FontWeight.Bold)
    val plain = CadenceTypography.titleLarge.copy(fontWeight = FontWeight.SemiBold)
}
