package com.nerijus.cadence.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import com.nerijus.cadence.app.LocalRouter
import com.nerijus.cadence.designsystem.Spacing
import com.nerijus.cadence.designsystem.backgroundGradient

/** A tab's first page: the brand-tinted background and a large title, like the iPhone app's,
 *  with buttons beside the title. */
@Composable
fun TabPage(
    title: String,
    actions: @Composable RowScope.() -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(backgroundGradient())
            .windowInsetsPadding(WindowInsets.statusBars),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(start = Spacing.large, end = Spacing.xSmall, top = Spacing.small),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                title,
                modifier = Modifier
                    .weight(1f)
                    .padding(vertical = Spacing.small)
                    .semantics { heading() },
                style = MaterialTheme.typography.headlineLarge,
            )
            actions()
        }
        content()
    }
}

/** A page opened inside a tab: Back, a small title and buttons, over the same background. */
@Composable
fun SubPage(
    title: String,
    actions: @Composable RowScope.() -> Unit = {},
    showsBack: Boolean = true,
    content: @Composable ColumnScope.() -> Unit,
) {
    val router = LocalRouter.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(backgroundGradient())
            .windowInsetsPadding(WindowInsets.statusBars),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = Spacing.xSmall),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (showsBack) {
                IconButton(onClick = { router.pop() }) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                }
            }
            Text(
                title,
                modifier = Modifier.weight(1f).padding(horizontal = Spacing.small),
                style = MaterialTheme.typography.titleLarge,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            actions()
        }
        content()
    }
}
