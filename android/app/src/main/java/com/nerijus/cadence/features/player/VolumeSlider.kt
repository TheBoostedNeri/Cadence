package com.nerijus.cadence.features.player

import android.database.ContentObserver
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeDown
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.nerijus.cadence.designsystem.Opacity
import com.nerijus.cadence.designsystem.Palette
import com.nerijus.cadence.designsystem.Spacing

/** The phone's media volume, like the system volume slider in the iPhone app's Now Playing.
 *  It follows the volume buttons too. */
@Composable
fun VolumeSlider(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val audio = remember(context) { context.getSystemService(AudioManager::class.java) }
    val maximum = remember(audio) { audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC) }
    var volume by remember(audio) { mutableIntStateOf(audio.getStreamVolume(AudioManager.STREAM_MUSIC)) }

    DisposableEffect(audio) {
        // Volume changes are saved to system settings, so watching them catches the buttons.
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                volume = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
            }
        }
        context.contentResolver.registerContentObserver(Settings.System.CONTENT_URI, true, observer)
        onDispose { context.contentResolver.unregisterContentObserver(observer) }
    }

    val dimmed = Palette.onPlayer.copy(alpha = Opacity.secondaryOnMedia)
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.small)) {
        Icon(Icons.AutoMirrored.Filled.VolumeDown, contentDescription = null, tint = dimmed)
        Slider(
            value = volume.toFloat(),
            onValueChange = { newVolume ->
                volume = newVolume.toInt()
                audio.setStreamVolume(AudioManager.STREAM_MUSIC, volume, 0)
            },
            valueRange = 0f..maximum.toFloat(),
            modifier = Modifier.weight(1f),
            colors = SliderDefaults.colors(
                thumbColor = Palette.onPlayer,
                activeTrackColor = Palette.onPlayer,
                inactiveTrackColor = Palette.onPlayer.copy(alpha = Opacity.scrubberTrack),
            ),
        )
        Icon(Icons.AutoMirrored.Filled.VolumeUp, contentDescription = null, tint = dimmed)
    }
}
