package com.nerijus.cadence.designsystem.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import com.nerijus.cadence.app.LocalImageLoader
import com.nerijus.cadence.designsystem.ArtworkSize
import com.nerijus.cadence.designsystem.Layout

/** A song's artwork, cropped to fill its frame, with a music note while it loads or when there
 *  is none. */
@Composable
fun ArtworkImage(
    url: String?,
    modifier: Modifier = Modifier,
    cornerRadius: Dp = Dp.Unspecified,
    contentScale: ContentScale = ContentScale.Crop,
) {
    val shape = if (cornerRadius == Dp.Unspecified) null else RoundedCornerShape(cornerRadius)
    BoxWithConstraints(
        modifier = modifier
            .then(if (shape != null) Modifier.clip(shape) else Modifier)
            .background(MaterialTheme.colorScheme.surfaceVariant),
        contentAlignment = Alignment.Center,
    ) {
        val sizePx = listOf(constraints.maxWidth, constraints.maxHeight)
            .filter { it != Constraints.Infinity }
            .maxOrNull() ?: with(LocalDensity.current) { ArtworkSize.large.roundToPx() }
        val image by loadedImage(url, sizePx)
        val loaded = image
        if (loaded != null) {
            Image(loaded, contentDescription = null, modifier = Modifier.fillMaxSize(), contentScale = contentScale)
        } else {
            Icon(
                Icons.Filled.MusicNote,
                contentDescription = null,
                modifier = Modifier.fillMaxWidth(Layout.placeholderSymbolScale),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun loadedImage(url: String?, sizePx: Int) = with(LocalImageLoader.current) {
    produceState(url?.let { cached(it, sizePx)?.asImageBitmap() }, url, sizePx) {
        value = url?.let { cached(it, sizePx)?.asImageBitmap() }
        if (url != null && value == null) {
            value = load(url, sizePx)?.asImageBitmap()
        }
    }
}
