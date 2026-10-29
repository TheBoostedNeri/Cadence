package com.nerijus.cadence.features.account

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.nerijus.cadence.app.LocalAppContainer
import com.nerijus.cadence.app.findActivity
import com.nerijus.cadence.designsystem.Layout
import com.nerijus.cadence.designsystem.Palette
import com.nerijus.cadence.designsystem.Spacing
import com.nerijus.cadence.designsystem.components.ErrorDialog
import com.nerijus.cadence.model.AppError
import kotlinx.coroutines.launch

/** Connects a YouTube account in a browser tab. Without a client ID in the build it explains
 *  what's missing instead. */
@Composable
fun ConnectAccountButton(modifier: Modifier = Modifier, showsSetupHint: Boolean = true) {
    val container = LocalAppContainer.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var isConnecting by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<AppError?>(null) }

    Column(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.small)) {
        Button(
            onClick = {
                val activity = context.findActivity() ?: return@Button
                isConnecting = true
                scope.launch {
                    try {
                        container.signIn(activity)
                    } catch (failure: AppError) {
                        if (failure != AppError.SignInCancelled) error = failure
                    } finally {
                        isConnecting = false
                    }
                }
            },
            enabled = container.auth.isConfigured && !isConnecting,
        ) {
            if (isConnecting) {
                CircularProgressIndicator(Modifier.size(Layout.inlineProgressSide), strokeWidth = Layout.inlineProgressStroke)
            } else {
                Icon(Icons.Filled.AccountCircle, contentDescription = null)
            }
            Spacer(Modifier.width(Spacing.small))
            Text("Connect YouTube Account")
        }
        if (showsSetupHint && !container.auth.isConfigured) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
                Icon(Icons.Filled.Warning, contentDescription = null, tint = Palette.warning, modifier = Modifier.size(Layout.inlineIconSide))
                Text(
                    "Add GOOGLE_CLIENT_ID to Config/Secrets.xcconfig to enable this.",
                    style = MaterialTheme.typography.bodySmall,
                    color = Palette.warning,
                )
            }
        }
    }
    ErrorDialog(error) { error = null }
}
