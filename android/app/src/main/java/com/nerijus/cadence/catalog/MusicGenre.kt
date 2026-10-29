package com.nerijus.cadence.catalog

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.QueueMusic
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.ChildCare
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Forest
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Nightlife
import androidx.compose.material.icons.filled.Park
import androidx.compose.material.icons.filled.Piano
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Spa
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarOutline
import androidx.compose.material.icons.filled.VolunteerActivism
import androidx.compose.material.icons.filled.WbTwilight
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.ui.graphics.vector.ImageVector

/** A genre Discover can browse, with Apple's ID for it, which its charts are filtered by. */
data class MusicGenre(val id: Int, val name: String, val icon: ImageVector) {
    companion object {
        /** Apple's main genres, each with a chart of its own in most countries. */
        val all = listOf(
            MusicGenre(14, "Pop", Icons.Filled.Star),
            MusicGenre(18, "Hip-Hop/Rap", Icons.Filled.Mic),
            MusicGenre(21, "Rock", Icons.Filled.Bolt),
            MusicGenre(20, "Alternative", Icons.Filled.GraphicEq),
            MusicGenre(17, "Dance", Icons.Filled.Nightlife),
            MusicGenre(7, "Electronic", Icons.Filled.Headphones),
            MusicGenre(15, "R&B/Soul", Icons.Filled.Favorite),
            MusicGenre(6, "Country", Icons.Filled.WbTwilight),
            MusicGenre(12, "Latin", Icons.Filled.LocalFireDepartment),
            MusicGenre(51, "K-Pop", Icons.Filled.AutoAwesome),
            MusicGenre(27, "J-Pop", Icons.Filled.StarOutline),
            MusicGenre(1153, "Metal", Icons.Filled.Bolt),
            MusicGenre(11, "Jazz", Icons.AutoMirrored.Filled.QueueMusic),
            MusicGenre(5, "Classical", Icons.Filled.Piano),
            MusicGenre(10, "Singer/Songwriter", Icons.Filled.Edit),
            MusicGenre(16, "Soundtrack", Icons.Filled.Movie),
            MusicGenre(24, "Reggae", Icons.Filled.Spa),
            MusicGenre(2, "Blues", Icons.Filled.MusicNote),
            MusicGenre(1289, "Folk", Icons.Filled.Forest),
            MusicGenre(19, "World", Icons.Filled.Public),
            MusicGenre(22, "Christian & Gospel", Icons.Filled.VolunteerActivism),
            MusicGenre(4, "Children's Music", Icons.Filled.ChildCare),
        )

        /** Words in Apple's genre names, checked in this order so that "K-Pop" isn't taken for
         *  Pop or "Pop/Rock" for Pop. */
        private val catalogKeywords = listOf(
            51 to listOf("k-pop"),
            27 to listOf("j-pop", "j-rock", "anime"),
            18 to listOf("hip-hop", "hip hop", "rap"),
            15 to listOf("r&b", "soul", "funk"),
            1153 to listOf("metal"),
            20 to listOf("alternative", "indie", "punk", "grunge", "emo"),
            21 to listOf("rock"),
            7 to listOf("electronic", "house", "techno", "trance", "dubstep", "ambient", "drum"),
            17 to listOf("dance", "edm"),
            6 to listOf("country", "americana", "bluegrass"),
            12 to listOf("latin", "reggaeton", "urbano", "salsa", "bachata"),
            11 to listOf("jazz"),
            5 to listOf("classical", "opera", "orchestral"),
            10 to listOf("singer/songwriter"),
            16 to listOf("soundtrack", "score", "musical"),
            24 to listOf("reggae", "dancehall"),
            2 to listOf("blues"),
            1289 to listOf("folk"),
            22 to listOf("christian", "gospel", "worship"),
            4 to listOf("children"),
            19 to listOf("world", "afro"),
            14 to listOf("pop"),
        )

        /** The browsable genre for one of Apple's more specific genre names, such as
         *  "Hard Rock" (Rock) or "Indie Pop" (Alternative). Null when none fits. */
        fun matching(catalogGenre: String): MusicGenre? {
            val name = catalogGenre.lowercase()
            val id = catalogKeywords.firstOrNull { (_, keywords) -> keywords.any(name::contains) }?.first
            return all.firstOrNull { it.id == id }
        }
    }
}
