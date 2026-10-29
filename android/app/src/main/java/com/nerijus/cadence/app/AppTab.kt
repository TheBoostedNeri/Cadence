package com.nerijus.cadence.app

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Search
import androidx.compose.ui.graphics.vector.ImageVector

/** The app's sections, in the same order as the iPhone app's tabs. */
enum class AppTab(val title: String, val icon: ImageVector) {
    Home("Home", Icons.Filled.Home),
    Discover("Discover", Icons.Filled.GridView),
    Playlists("Playlists", Icons.AutoMirrored.Filled.QueueMusic),
    Recents("Recents", Icons.Filled.History),
    Search("Search", Icons.Filled.Search),
}
