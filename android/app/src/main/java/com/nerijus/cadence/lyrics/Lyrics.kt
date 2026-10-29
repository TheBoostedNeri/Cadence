package com.nerijus.cadence.lyrics

import com.nerijus.cadence.config.LyricsPolicy
import com.nerijus.cadence.network.looselyContains
import com.nerijus.cadence.network.looselyMatches
import kotlin.math.max
import kotlin.math.min

data class LyricLine(
    /** Its position in the song, so the distance between IDs is the distance in lines. */
    val id: Int,
    /** Seconds from the start of the recording the lyrics were timed against. */
    val time: Double,
    /** When the next line starts; null for the last line. */
    val end: Double?,
    val text: String,
) {
    /** How long the estimated word sweep takes. LRCLIB has no word timing, so the highlight
     *  spreads over the line's window, capped so instrumental gaps don't stretch it out. */
    val sweepDuration: Double
        get() {
            val characters = max(text.length, 1).toDouble()
            val window = end?.let { it - time } ?: (characters * LyricsPolicy.FALLBACK_SECONDS_PER_CHARACTER)
            val capped = min(window, characters * LyricsPolicy.MAX_SECONDS_PER_CHARACTER)
            return max(capped, LyricsPolicy.MINIMUM_SWEEP_DURATION)
        }
}

sealed interface Lyrics {
    data class Synced(val lines: List<LyricLine>) : Lyrics
    data class Plain(val text: String) : Lyrics
    data object Instrumental : Lyrics
}

/** Parses LRC text such as `[01:02.34]Some line`. Lines may carry several timestamps. */
object LrcParser {
    private const val SECONDS_PER_MINUTE = 60.0
    private val timestamp = Regex("""^\[(\d{1,3}):(\d{1,2}(?:\.\d{1,3})?)]""")

    fun lines(lrc: String): List<LyricLine> {
        val timed = mutableListOf<Pair<Double, String>>()
        for (rawLine in lrc.lines()) {
            var remainder = rawLine
            val times = mutableListOf<Double>()
            while (true) {
                val match = timestamp.find(remainder) ?: break
                val minutes = match.groupValues[1].toDoubleOrNull() ?: 0.0
                val seconds = match.groupValues[2].toDoubleOrNull() ?: 0.0
                times += minutes * SECONDS_PER_MINUTE + seconds
                remainder = remainder.substring(match.range.last + 1)
            }
            val text = remainder.trim()
            times.forEach { timed += it to text }
        }
        val sorted = timed.sortedBy { it.first }
        return sorted.mapIndexed { index, (time, text) ->
            LyricLine(id = index, time = time, end = sorted.getOrNull(index + 1)?.first, text = text)
        }
    }
}

/**
 * Turns a YouTube video title into an artist and song name a lyrics database understands,
 * e.g. "LISA - Tarantino (Official Music Video)" → artist "LISA", title "Tarantino".
 */
data class SongQuery(val artist: String, val title: String) {
    /** Whether two videos carry the same song, such as its music video and its Topic upload. */
    fun isSameSong(other: SongQuery): Boolean =
        title.isNotEmpty() && title.looselyContains(other.title) && other.title.looselyContains(title) &&
            artist.looselyMatches(other.artist)

    companion object {
        private val dashSeparators = listOf(" - ", " – ", " — ")
        private val channelSuffixes = listOf("VEVO", "Official")
        private val bracketedText = Regex("""\s*[(\[【][^)\]】]*[)\]】]""")
        private val credit = Regex("""(?i)\s+(ft\.?|feat\.?|featuring|prod\.?)\s+.*$""")
        private val trimmedCharacters = charArrayOf(' ', '\t', '"', '\'', '“', '”', '‘', '’')

        private const val VERSION_SEPARATOR = " - "

        /** Drops "(Official Video)", "[Lyrics]", "(feat. X)" and similar. */
        fun removingBracketedText(text: String): String = bracketedText.replace(text, "")

        /** A catalog title without the version details videos often leave out:
         *  "Song (feat. X)" and "Song - 2011 Remaster" → "Song". */
        fun core(title: String): String =
            removingBracketedText(title).substringBefore(VERSION_SEPARATOR).trim().ifEmpty { title }

        fun from(trackTitle: String, trackArtist: String): SongQuery {
            var title = bracketedText.replace(trackTitle, "").substringBefore('|')
            var artist = cleanChannel(trackArtist)
            dashSeparators.firstOrNull { it in title }?.let { separator ->
                artist = title.substringBefore(separator)
                title = title.substringAfter(separator)
            }
            return SongQuery(artist = removingCredits(artist), title = removingCredits(title))
        }

        /** Cuts featured artists and producer credits: "Song ft. X" → "Song". */
        private fun removingCredits(text: String) = credit.replace(text, "").trim(*trimmedCharacters)

        /** "LISAOfficialVEVO" → "LISA". */
        private fun cleanChannel(channel: String): String {
            var name = channel
            var didStrip = true
            while (didStrip) {
                didStrip = false
                for (suffix in channelSuffixes) {
                    if (name.length > suffix.length && name.endsWith(suffix)) {
                        name = name.dropLast(suffix.length).trim()
                        didStrip = true
                    }
                }
            }
            return name
        }
    }
}
