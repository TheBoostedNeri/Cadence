package com.nerijus.cadence.features.onboarding

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.AddCircleOutline
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Lyrics
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PauseCircleOutline
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.SmartDisplay
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import com.nerijus.cadence.app.LocalAppContainer
import com.nerijus.cadence.designsystem.IconSize
import com.nerijus.cadence.designsystem.Layout
import com.nerijus.cadence.designsystem.Spacing
import com.nerijus.cadence.designsystem.backgroundGradient
import com.nerijus.cadence.features.account.ConnectAccountButton

private class OnboardingStep(val icon: ImageVector, val title: String, val message: String, val highlights: List<Pair<ImageVector, String>>)

private val steps = listOf(
    OnboardingStep(
        Icons.Filled.MusicNote,
        "Welcome to Cadence",
        "One native home for your music.",
        listOf(
            Icons.Filled.GridView to "Trending music and every genre to discover",
            Icons.Filled.Search to "Search songs and artists",
            Icons.Filled.Lyrics to "Synced lyrics for most songs",
        ),
    ),
    OnboardingStep(
        Icons.Filled.SmartDisplay,
        "How Playback Works",
        "Cadence uses YouTube's official player, so a few of YouTube's rules apply.",
        listOf(
            Icons.Filled.SmartDisplay to "Songs play in YouTube's own player",
            Icons.Filled.Visibility to "The video stays on screen while it plays",
            Icons.Filled.PauseCircleOutline to "Closing the player or leaving the app pauses playback",
        ),
    ),
    OnboardingStep(
        Icons.Filled.AccountCircle,
        "Connect Your Account",
        "Cadence asks Google for permission to manage your YouTube playlists. Nothing else is needed.",
        listOf(
            Icons.AutoMirrored.Filled.QueueMusic to "See and play your YouTube playlists",
            Icons.Filled.AddCircleOutline to "Create playlists and add songs",
            Icons.Filled.Security to "Disconnect any time from Settings",
        ),
    ),
)

/** A few pages on first launch: what Cadence does, how YouTube's player works, and connecting
 *  an account. YouTube is the only service on Android, so there's no service to choose. */
@Composable
fun OnboardingScreen() {
    val container = LocalAppContainer.current
    var stepIndex by rememberSaveable { mutableIntStateOf(0) }
    val isLast = stepIndex == steps.lastIndex
    val finish = { container.settings.hasCompletedOnboarding = true }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .background(backgroundGradient())
            .windowInsetsPadding(WindowInsets.safeDrawing)
            .padding(Spacing.xLarge),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(Modifier.fillMaxWidth()) {
            if (stepIndex > 0) TextButton(onClick = { stepIndex -= 1 }) { Text("Back") }
            Spacer(Modifier.weight(1f))
            if (!isLast) TextButton(onClick = finish) { Text("Skip") }
        }
        AnimatedContent(
            targetState = stepIndex,
            modifier = Modifier.weight(1f),
            transitionSpec = { fadeIn() togetherWith fadeOut() },
            label = "step",
        ) { index ->
            StepContent(steps[index])
        }
        StepIndicator(stepIndex)
        Spacer(Modifier.height(Spacing.xLarge))
        Column(
            modifier = Modifier.widthIn(max = Layout.buttonMaxWidth).fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(Spacing.small),
        ) {
            if (isLast) {
                if (container.auth.isSignedIn) {
                    Button(onClick = finish, modifier = Modifier.fillMaxWidth()) { Text("Get Started") }
                } else {
                    ConnectAccountButton(Modifier.fillMaxWidth())
                    TextButton(onClick = finish, modifier = Modifier.fillMaxWidth()) { Text("Not Now") }
                }
            } else {
                Button(onClick = { stepIndex += 1 }, modifier = Modifier.fillMaxWidth()) { Text("Continue") }
            }
        }
    }
}

@Composable
private fun StepContent(step: OnboardingStep) {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(Spacing.large, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(step.icon, contentDescription = null, modifier = Modifier.size(IconSize.hero), tint = MaterialTheme.colorScheme.primary)
        Text(step.title, style = MaterialTheme.typography.headlineMedium, textAlign = TextAlign.Center)
        Text(
            step.message,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Column(Modifier.padding(top = Spacing.large), verticalArrangement = Arrangement.spacedBy(Spacing.medium)) {
            step.highlights.forEach { (icon, text) ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.medium)) {
                    Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                    Text(text, style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
    }
}

@Composable
private fun StepIndicator(current: Int) {
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.small)) {
        steps.indices.forEach { index ->
            val width by animateDpAsState(if (index == current) Layout.stepIndicatorActiveWidth else Layout.stepIndicatorDot, label = "dot")
            Box(
                Modifier
                    .width(width)
                    .height(Layout.stepIndicatorDot)
                    .background(
                        if (index == current) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant,
                        CircleShape,
                    ),
            )
        }
    }
}
