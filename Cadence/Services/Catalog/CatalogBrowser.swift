import Foundation
import Observation

/// Albums and artists for "Go to Album" and "Go to Artist". They come from Apple's free catalog
/// for every service, since YouTube's API has neither; on YouTube, each song's video is found as
/// it comes up to play.
@Observable
final class CatalogBrowser {
    @ObservationIgnored private let config: AppConfig
    @ObservationIgnored private let client: AppleCatalogClient
    /// Pages already looked up this launch, by the song they were opened from.
    @ObservationIgnored private var albums: [String: Album] = [:]
    @ObservationIgnored private var albumsByID: [String: Album] = [:]
    @ObservationIgnored private var artists: [String: Artist] = [:]
    @ObservationIgnored private var genreCharts: [MusicGenre.ID: [Track]] = [:]

    init(config: AppConfig, client: AppleCatalogClient = AppleCatalogClient()) {
        self.config = config
        self.client = client
    }

    private var country: String { config.regionCode.lowercased() }

    /// The album `track` is from, or nil when Apple's catalog has none by its artist.
    func album(containing track: Track) async throws -> Album? {
        let key = track.catalogSongID ?? track.id
        if let album = albums[key] { return album }
        let album = try await client.album(containing: track, country: country)
        albums[key] = album
        return album
    }

    /// An album picked by its catalog ID, such as from an artist's page.
    func album(id: String) async throws -> Album? {
        if let album = albumsByID[id] { return album }
        guard let numericID = Int(id) else { return nil }
        let album = try await client.album(id: numericID, country: country)
        albumsByID[id] = album
        return album
    }

    /// A genre's best-selling songs in the user's region, most popular first.
    func topSongs(in genre: MusicGenre) async throws -> [Track] {
        if let songs = genreCharts[genre.id] { return songs }
        let songs = try await client.topSongs(inGenre: genre.id, country: country)
        genreCharts[genre.id] = songs
        return songs
    }

    /// Songs for Autoplay to play after `track`: popular songs in the same genre, with about one
    /// in three by the same artist, like a radio station built from the song. Only the artist's
    /// songs when the genre has no chart, and none when Apple doesn't know the artist.
    func autoplayTracks(after track: Track) async throws -> [Track] {
        guard let artist = try await artist(of: track) else { return [] }
        let byArtist = artist.tracks
        guard let genre = artist.genre.flatMap(MusicGenre.matching(catalogGenre:)),
              let chart = try? await topSongs(in: genre)
        else { return byArtist }
        // Shuffled, so each top-up brings different songs rather than the chart's top every time.
        let similar = chart.filter { !$0.artist.looselyMatches(artist.name) }.shuffled()
        return Self.interleave(similar, with: byArtist, every: PlaybackPolicy.autoplaySimilarPerArtistSong)
    }

    /// `run` songs from `main`, then one from `other`, and so on, until both run out.
    private static func interleave(_ main: [Track], with other: [Track], every run: Int) -> [Track] {
        var result: [Track] = []
        var mainIndex = main.startIndex
        var otherIndex = other.startIndex
        while mainIndex < main.endIndex || otherIndex < other.endIndex {
            let runEnd = min(mainIndex + run, main.endIndex)
            result += main[mainIndex..<runEnd]
            mainIndex = runEnd
            if otherIndex < other.endIndex {
                result.append(other[otherIndex])
                otherIndex += 1
            }
        }
        return result
    }

    /// The artist of `track` and their songs, or nil when Apple's catalog has no such artist.
    func artist(of track: Track) async throws -> Artist? {
        let key = track.catalogSongID ?? track.id
        if let artist = artists[key] { return artist }
        let artist = try await client.artist(of: track, country: country)
        artists[key] = artist
        return artist
    }
}
