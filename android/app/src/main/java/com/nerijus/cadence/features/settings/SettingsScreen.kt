package com.nerijus.cadence.features.settings

import android.Manifest
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Article
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.Lyrics
import androidx.compose.material.icons.filled.PhonelinkLock
import androidx.compose.material.icons.filled.PrivacyTip
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.AlertDialog
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalUriHandler
import com.nerijus.cadence.app.LocalAppContainer
import com.nerijus.cadence.app.LocalRouter
import com.nerijus.cadence.config.LegalLink
import com.nerijus.cadence.designsystem.ArtworkSize
import com.nerijus.cadence.designsystem.Palette
import com.nerijus.cadence.designsystem.Spacing
import com.nerijus.cadence.designsystem.components.ArtworkImage
import com.nerijus.cadence.designsystem.components.SubPage
import com.nerijus.cadence.features.account.ConnectAccountButton
import com.nerijus.cadence.model.ChannelProfile
import com.nerijus.cadence.model.LoadState
import com.nerijus.cadence.model.AppError
import kotlinx.coroutines.launch

/** The YouTube account, experimental options, what's configured, and the legal links YouTube's
 *  policies require. */
@Composable
fun SettingsScreen() {
    val container = LocalAppContainer.current
    val router = LocalRouter.current
    val auth = container.auth
    val settings = container.settings
    val uriHandler = LocalUriHandler.current
    val scope = rememberCoroutineScope()
    var profile by remember { mutableStateOf<LoadState<ChannelProfile?>>(LoadState.Idle) }
    var isConfirmingDisconnect by remember { mutableStateOf(false) }
    val close = { router.isSettingsPresented = false }
    // Background play works without it; the notification just doesn't show.
    val notificationPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}

    BackHandler(onBack = close)
    LaunchedEffect(auth.isSignedIn) {
        if (!auth.isSignedIn) {
            profile = LoadState.Idle
            return@LaunchedEffect
        }
        profile = LoadState.Loading
        profile = try {
            LoadState.Loaded(container.api.myChannel())
        } catch (error: Exception) {
            LoadState.Failed(AppError.from(error))
        }
    }

    SubPage("Settings", showsBack = false, actions = { TextButton(onClick = close) { Text("Done") } }) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .windowInsetsPadding(WindowInsets.navigationBars)
                .padding(bottom = Spacing.xLarge),
        ) {
            Section("YouTube Account") {
                if (auth.isSignedIn) {
                    when (val state = profile) {
                        LoadState.Idle, LoadState.Loading -> ListItem(
                            headlineContent = { Text("Loading account…") },
                            leadingContent = { CircularProgressIndicator(Modifier.size(ArtworkSize.mini)) },
                            colors = clear(),
                        )
                        is LoadState.Loaded -> ListItem(
                            headlineContent = { Text(state.value?.title ?: "YouTube Account") },
                            supportingContent = { Text("Connected", color = Palette.success) },
                            leadingContent = {
                                ArtworkImage(state.value?.avatarUrl, Modifier.size(ArtworkSize.row).clip(CircleShape))
                            },
                            colors = clear(),
                        )
                        is LoadState.Failed -> ListItem(
                            headlineContent = { Text(state.error.title) },
                            supportingContent = { Text(state.error.message) },
                            leadingContent = { Icon(state.error.icon, contentDescription = null, tint = Palette.warning) },
                            colors = clear(),
                        )
                    }
                    ListItem(
                        headlineContent = { Text("Disconnect Account", color = MaterialTheme.colorScheme.error) },
                        modifier = Modifier.clickable { isConfirmingDisconnect = true },
                        colors = clear(),
                    )
                } else {
                    Column(Modifier.padding(Spacing.large), verticalArrangement = Arrangement.spacedBy(Spacing.medium)) {
                        Text(
                            "Connect to play your YouTube playlists, create new ones and add songs.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        ConnectAccountButton()
                    }
                }
            }

            Section(
                "Experimental",
                footer = "Lights up synced lyrics word by word. LRCLIB only times whole lines, so the pace within a line is estimated.",
            ) {
                ToggleRow("Word-by-Word Lyrics", Icons.Filled.TextFields, container.lyrics.isWordSweepEnabled) {
                    container.lyrics.isWordSweepEnabled = it
                }
            }
            Section(
                footer = "Unofficial and for personal use only: keeps YouTube playing with the player closed or the phone locked, with controls in a notification. That breaks YouTube's API Terms and could get your Google Cloud project suspended.",
            ) {
                ToggleRow("YouTube Background Play", Icons.Filled.PhonelinkLock, settings.isBackgroundPlayEnabled) { isOn ->
                    settings.isBackgroundPlayEnabled = isOn
                    container.player.backgroundPlaySettingChanged()
                    // The controls show in a notification, which Android 13 and later ask about.
                    if (isOn && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
                    }
                }
            }

            Section("Configuration", footer = "Set these in Config/Secrets.xcconfig, then build the app again. Browsing works with an API key or a connected account.") {
                StatusRow("YouTube API key", container.api.hasApiKey)
                StatusRow("Google client ID", auth.isConfigured)
                ListItem(
                    headlineContent = { Text("Charts region") },
                    trailingContent = { Text(container.api.regionName) },
                    colors = clear(),
                )
            }

            Section("About") {
                LinkRow("YouTube Terms of Service", Icons.AutoMirrored.Filled.Article) { uriHandler.openUri(LegalLink.YOUTUBE_TERMS) }
                LinkRow("Google Privacy Policy", Icons.Filled.PrivacyTip) { uriHandler.openUri(LegalLink.GOOGLE_PRIVACY) }
                LinkRow("Manage Google Account Access", Icons.Filled.Key) { uriHandler.openUri(LegalLink.MANAGE_ACCESS) }
                LinkRow("Lyrics by LRCLIB", Icons.Filled.Lyrics) { uriHandler.openUri(LegalLink.LRCLIB) }
                LinkRow("Show Onboarding Again", Icons.Filled.AutoAwesome) {
                    close()
                    settings.hasCompletedOnboarding = false
                }
            }
        }
    }

    if (isConfirmingDisconnect) {
        AlertDialog(
            onDismissRequest = { isConfirmingDisconnect = false },
            title = { Text("Disconnect your YouTube account?") },
            text = { Text("Your playlists stay on YouTube. Recently played history on this device is kept.") },
            confirmButton = {
                TextButton(onClick = {
                    isConfirmingDisconnect = false
                    scope.launch { container.signOut() }
                }) { Text("Disconnect", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { isConfirmingDisconnect = false }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun clear() = ListItemDefaults.colors(containerColor = Color.Transparent)

@Composable
private fun Section(title: String? = null, footer: String? = null, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(top = Spacing.large)) {
        title?.let {
            Text(
                it,
                modifier = Modifier.padding(horizontal = Spacing.large, vertical = Spacing.small),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
        }
        content()
        footer?.let {
            Text(
                it,
                modifier = Modifier.padding(horizontal = Spacing.large),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        HorizontalDivider(Modifier.padding(top = Spacing.large))
    }
}

@Composable
private fun ToggleRow(title: String, icon: ImageVector, isOn: Boolean, onChange: (Boolean) -> Unit) {
    ListItem(
        headlineContent = { Text(title) },
        leadingContent = { Icon(icon, contentDescription = null) },
        trailingContent = { Switch(checked = isOn, onCheckedChange = onChange) },
        modifier = Modifier.clickable { onChange(!isOn) },
        colors = clear(),
    )
}

@Composable
private fun StatusRow(title: String, isConfigured: Boolean) {
    val color = if (isConfigured) Palette.success else Palette.warning
    ListItem(
        headlineContent = { Text(title) },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
                Icon(if (isConfigured) Icons.Filled.CheckCircle else Icons.Filled.Cancel, contentDescription = null, tint = color)
                Text(if (isConfigured) "Configured" else "Missing", color = color)
            }
        },
        colors = clear(),
    )
}

@Composable
private fun LinkRow(title: String, icon: ImageVector, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(title, color = MaterialTheme.colorScheme.primary) },
        leadingContent = { Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary) },
        modifier = Modifier.clickable(onClick = onClick),
        colors = clear(),
    )
}
