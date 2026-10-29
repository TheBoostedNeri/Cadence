package com.nerijus.cadence.designsystem.components

import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp

/** Fades content out over `top` at the top edge and `bottom` at the bottom, instead of clipping
 *  it hard, like the iPhone app's edgeFade. */
fun Modifier.edgeFade(top: Dp, bottom: Dp): Modifier = this
    // Drawn offscreen, so the fade only takes away from this content, not what's behind it.
    .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
    .drawWithContent {
        drawContent()
        val topHeight = top.toPx().coerceAtMost(size.height)
        val bottomHeight = bottom.toPx().coerceAtMost(size.height)
        drawRect(
            brush = Brush.verticalGradient(listOf(Color.Transparent, Color.Black), startY = 0f, endY = topHeight),
            size = Size(size.width, topHeight),
            blendMode = BlendMode.DstIn,
        )
        drawRect(
            brush = Brush.verticalGradient(
                listOf(Color.Black, Color.Transparent),
                startY = size.height - bottomHeight,
                endY = size.height,
            ),
            topLeft = Offset(0f, size.height - bottomHeight),
            size = Size(size.width, bottomHeight),
            blendMode = BlendMode.DstIn,
        )
    }
