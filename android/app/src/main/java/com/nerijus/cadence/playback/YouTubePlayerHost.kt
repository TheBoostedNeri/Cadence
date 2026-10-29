package com.nerijus.cadence.playback

import android.annotation.SuppressLint
import android.content.Context
import android.view.MotionEvent
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView

/** Holds the player and never takes a touch itself or lets one through to it: the app's own
 *  controls drive playback, and YouTube's overlay must never appear. Touches fall through to
 *  whatever is beneath, such as Now Playing's swipe down to close. */
private class PlayerContainer(context: Context) : FrameLayout(context) {
    init {
        clipChildren = true
        setBackgroundColor(android.graphics.Color.BLACK)
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun dispatchTouchEvent(event: MotionEvent) = false

    fun attach(webView: PlayerWebView) {
        if (webView.parent === this) return
        (webView.parent as? ViewGroup)?.removeView(webView)
        addView(webView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    }
}

/** Shows the single long-lived player web view here, moving it from wherever it was, so
 *  playback carries on as it moves between Now Playing and its hidden spot. */
@Composable
fun YouTubePlayerHost(webView: PlayerWebView, modifier: Modifier = Modifier) {
    AndroidView(
        factory = { context -> PlayerContainer(context).apply { attach(webView) } },
        modifier = modifier,
        update = { container -> container.attach(webView) },
    )
}
