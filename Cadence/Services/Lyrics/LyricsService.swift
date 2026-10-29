import Foundation
import Observation

nonisolated struct LyricLine: Identifiable, Hashable, Sendable {
    let id: Int
    /// Seconds from the start of the recording the lyrics were timed against.
    let time: TimeInterval
    /// When the next line starts; nil for the last line.
    let end: TimeInterval?
    let text: String

    /// How long the estimated word sweep takes. LRCLIB has no word timing, so the highlight
    /// spreads over the line's window, capped so instrumental gaps don't stretch it out.
    var sweepDuration: TimeInterval {
        let characters = TimeInterval(max(text.count, 1))
        let window = end.map { $0 - time } ?? characters * LyricsPolicy.fallbackSecondsPerCharacter
        let capped = min(window, characters * LyricsPolicy.maxSecondsPerCharacter)
        return max(capped, LyricsPolicy.minimumSweepDuration)
    }
}

nonisolated enum Lyrics: Equatable, Sendable {
    case synced([LyricLine])
    case plain(String)
    case instrumental
}

/// Time-synced lyrics from LRCLIB (https://lrclib.net), a free, community-maintained database.
/// Lyrics there are user-contributed and unlicensed, so this suits personal use only.
@Observable
final class LyricsService {
    /// Per-video timing corrections in seconds; positive values show lyrics later.
    private(set) var offsets: [String: TimeInterval]

    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let decoder = JSONDecoder()
    /// `nil` values remember songs LRCLIB has no lyrics for.
    @ObservationIgnored private var cache: [CacheKey: Lyrics?] = [:]

    /// The same song can be picked differently for a recording of another length.
    private struct CacheKey: Hashable {
        let trackID: Track.ID
        let seconds: Int?
    }

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
        offsets = defaults.dictionary(forKey: StorageKey.lyricsOffsets) as? [String: TimeInterval] ?? [:]
    }

    /// The best lyrics for `track` as it plays, `duration` long, or nil when LRCLIB has none.
    /// Pass the length the player reports: a YouTube video found for an album song can be a
    /// music video that runs longer than the album version `track` describes.
    func lyrics(for track: Track, duration: TimeInterval?) async throws -> Lyrics? {
        let duration = duration ?? track.duration
        let key = CacheKey(trackID: track.id, seconds: duration.map { Int($0.rounded()) })
        if let cached = cache[key] { return cached }
        let query = SongQuery(track: track)
        var lyrics = Self.bestLyrics(
            in: try await search(["track_name": query.title, "artist_name": query.artist]),
            matching: duration
        )
        if lyrics == nil {
            lyrics = Self.bestLyrics(
                in: try await search(["q": "\(query.artist) \(query.title)"]),
                matching: duration
            )
        }
        cache[key] = .some(lyrics)
        return lyrics
    }

    // MARK: Timing

    func offset(for track: Track) -> TimeInterval {
        offsets[track.id] ?? 0
    }

    func setOffset(_ offset: TimeInterval, for track: Track) {
        let rounded = (offset / LyricsPolicy.offsetPrecision).rounded() * LyricsPolicy.offsetPrecision
        offsets[track.id] = rounded == 0 ? nil : rounded
        defaults.set(offsets, forKey: StorageKey.lyricsOffsets)
    }

    func adjustOffset(by delta: TimeInterval, for track: Track) {
        setOffset(offset(for: track) + delta, for: track)
    }

    // MARK: Matching

    /// Prefers synced lyrics whose recording length is closest to the video's, which also picks
    /// versions timed to the music video when LRCLIB has them.
    static func bestLyrics(in records: [LRCLibRecord], matching duration: TimeInterval?) -> Lyrics? {
        func mismatch(_ record: LRCLibRecord) -> TimeInterval {
            guard let duration, let recordDuration = record.duration else { return 0 }
            return abs(recordDuration - duration)
        }
        let candidates = records
            .filter { mismatch($0) <= LyricsPolicy.maxDurationMismatch }
            .sorted { mismatch($0) < mismatch($1) }

        if let lines = candidates.lazy
            .compactMap({ $0.syncedLyrics.map(LRCParser.lines(from:)) })
            .first(where: { !$0.isEmpty }) {
            return .synced(lines)
        }
        if let text = candidates.lazy
            .compactMap({ $0.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return .plain(text)
        }
        if candidates.contains(where: { $0.instrumental == true }) {
            return .instrumental
        }
        return nil
    }

    // MARK: Transport

    private func search(_ parameters: [String: String]) async throws -> [LRCLibRecord] {
        let queryItems = parameters
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: LyricsEndpoint.search.appending(queryItems: queryItems))
        // LRCLIB asks clients to identify themselves.
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            if error.isCancellation { throw error }
            throw AppError(error)
        }
        let (data, response) = result
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? HTTPStatus.success.lowerBound
        guard HTTPStatus.success.contains(statusCode) else {
            throw AppError.lyricsService(statusCode: statusCode)
        }
        do {
            return try decoder.decode([LRCLibRecord].self, from: data)
        } catch {
            throw AppError.decoding
        }
    }

    private static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return "Cadence/\(version)"
    }
}

nonisolated struct LRCLibRecord: Decodable, Sendable {
    let id: Int
    let trackName: String?
    let artistName: String?
    let duration: TimeInterval?
    let instrumental: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?
}

/// Parses LRC text such as `[01:02.34]Some line`. Lines may carry several timestamps.
nonisolated enum LRCParser {
    private static let secondsPerMinute: TimeInterval = 60

    static func lines(from lrc: String) -> [LyricLine] {
        let timestamp = #/\[(\d{1,3}):(\d{1,2}(?:\.\d{1,3})?)\]/#
        var timed: [(time: TimeInterval, text: String)] = []
        for rawLine in lrc.split(whereSeparator: \.isNewline) {
            var remainder = Substring(rawLine)
            var times: [TimeInterval] = []
            while let match = remainder.prefixMatch(of: timestamp) {
                let minutes = TimeInterval(match.output.1) ?? 0
                let seconds = TimeInterval(match.output.2) ?? 0
                times.append(minutes * secondsPerMinute + seconds)
                remainder = remainder[match.range.upperBound...]
            }
            let text = remainder.trimmingCharacters(in: .whitespaces)
            for time in times {
                timed.append((time, text))
            }
        }
        let sorted = timed.sorted { $0.time < $1.time }
        return sorted.indices.map { index in
            LyricLine(
                id: index,
                time: sorted[index].time,
                end: sorted.indices.contains(index + 1) ? sorted[index + 1].time : nil,
                text: sorted[index].text
            )
        }
    }
}

/// Turns a YouTube video title into an artist and song name a lyrics database understands,
/// e.g. "LISA - Tarantino (Official Music Video)" → artist "LISA", title "Tarantino".
nonisolated struct SongQuery: Equatable, Sendable {
    let artist: String
    let title: String

    private static let dashSeparators = [" - ", " – ", " — "]
    private static let channelSuffixes = ["VEVO", "Official"]

    init(track: Track) {
        var title = SongTitle.removingBracketedText(from: track.title)
        if let pipe = title.firstIndex(of: "|") {
            title = String(title[..<pipe])
        }

        var artist = Self.cleanChannel(track.artist)
        for separator in Self.dashSeparators {
            if let range = title.range(of: separator) {
                artist = String(title[..<range.lowerBound])
                title = String(title[range.upperBound...])
                break
            }
        }

        self.artist = Self.removingCredits(from: artist)
        self.title = Self.removingCredits(from: title)
    }

    /// Cuts featured artists and producer credits: "Song ft. X" → "Song".
    private static func removingCredits(from text: String) -> String {
        let credit = #/(?i)\s+(ft\.?|feat\.?|featuring|prod\.?)\s+.*$/#
        return text
            .replacing(credit, with: "")
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'“”‘’")))
    }

    /// "LISAOfficialVEVO" → "LISA".
    private static func cleanChannel(_ channel: String) -> String {
        var name = channel
        var didStrip = true
        while didStrip {
            didStrip = false
            for suffix in channelSuffixes where name.count > suffix.count && name.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
                didStrip = true
            }
        }
        return name
    }
}
