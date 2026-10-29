package com.nerijus.cadence.features.search

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import com.nerijus.cadence.app.LocalAppContainer
import com.nerijus.cadence.app.LocalPlayer
import com.nerijus.cadence.designsystem.Radius
import com.nerijus.cadence.designsystem.Spacing
import com.nerijus.cadence.designsystem.components.EmptyState
import com.nerijus.cadence.designsystem.components.ErrorState
import com.nerijus.cadence.designsystem.components.LoadingState
import com.nerijus.cadence.designsystem.components.TabPage
import com.nerijus.cadence.designsystem.components.TrackRow
import com.nerijus.cadence.model.LoadState

/** Songs and music videos on YouTube, updating as you type. */
@Composable
fun SearchScreen() {
    val model = LocalAppContainer.current.search
    val player = LocalPlayer.current
    val focusManager = LocalFocusManager.current

    TabPage("Search") {
        OutlinedTextField(
            value = model.query,
            onValueChange = model::updateQuery,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = Spacing.large, vertical = Spacing.small),
            placeholder = { Text("Songs, artists, music videos") },
            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
            trailingIcon = {
                if (model.query.isNotEmpty()) {
                    IconButton(onClick = { model.updateQuery("") }) {
                        Icon(Icons.Filled.Close, contentDescription = "Clear")
                    }
                }
            },
            singleLine = true,
            shape = RoundedCornerShape(Radius.medium),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onSearch = {
                model.submit()
                focusManager.clearFocus()
            }),
        )

        when (val state = model.results) {
            LoadState.Idle -> EmptyState(
                title = "Search Music",
                icon = Icons.Filled.Search,
                message = "Find songs and music videos on YouTube.",
            )
            LoadState.Loading -> LoadingState("Searching…")
            is LoadState.Failed -> ErrorState(state.error, onRetry = model::retry)
            is LoadState.Loaded -> if (state.value.isEmpty()) {
                EmptyState(
                    title = "No Results",
                    icon = Icons.Filled.Search,
                    message = "Try a different song or artist.",
                )
            } else {
                LazyColumn {
                    itemsIndexed(state.value, key = { index, track -> "$index#${track.id}" }) { index, track ->
                        TrackRow(
                            track = track,
                            isCurrent = player.currentTrack?.id == track.id,
                            onClick = {
                                focusManager.clearFocus()
                                player.play(state.value, index)
                            },
                        )
                    }
                }
            }
        }
    }
}
