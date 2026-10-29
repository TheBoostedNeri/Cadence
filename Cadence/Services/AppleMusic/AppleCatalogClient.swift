import Foundation

/// Apple Music catalog data from Apple's public iTunes Search API and Apple Music charts feed.
/// Neither needs a key or MusicKit, so they work on a free developer account.
final class AppleCatalogClient {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(_ query: String, country: String) async throws -> [Track] {
        let url = AppleMusicEndpoint.search.appending(queryItems: [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: String(AppleMusicLimits.searchResults)),
            URLQueryItem(name: "country", value: country),
        ])
        let response: ITunesResponse = try await get(url)
        return response.results.compactMap(\.track)
    }

    /// The most-played songs on Apple Music in `country`, with lengths filled in from a lookup.
    func topSongs(country: String) async throws -> [Track] {
        let url = AppleMusicEndpoint.charts
            .appending(path: country)
            .appending(path: "music/most-played/\(AppleMusicLimits.chartSize)/songs.json")
        let chart: AppleChartResponse = try await get(url)
        let ids = chart.feed.results.map(\.id)
        let detailed = Dictionary(
            try await lookup(ids: ids, country: country).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return chart.feed.results.map { entry in
            detailed[entry.id] ?? Track(
                id: entry.id,
                title: entry.name,
                artist: entry.artistName,
                artworkURL: AppleArtwork.url(from: entry.artworkUrl100, pixels: AppleMusicLimits.artworkPixels),
                largeArtworkURL: AppleArtwork.url(from: entry.artworkUrl100, pixels: AppleMusicLimits.largeArtworkPixels),
                duration: nil,
                source: .appleMusic
            )
        }
    }

    /// The best-selling songs in a genre in `country`, with full details from a lookup.
    func topSongs(inGenre genreID: Int, country: String) async throws -> [Track] {
        let url = AppleMusicEndpoint.genreCharts
            .appending(path: country)
            .appending(path: "rss/topsongs/limit=\(AppleMusicLimits.genreChartSize)/genre=\(genreID)/json")
        let chart: ITunesGenreChart = try await get(url)
        let ids = chart.feed.songIDs
        let detailed = Dictionary(
            try await lookup(ids: ids, country: country).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return ids.compactMap { detailed[$0] }
    }

    /// Catalog details for Apple Music song IDs, in no particular order.
    func lookup(ids: [String], country: String) async throws -> [Track] {
        var tracks: [Track] = []
        for start in stride(from: 0, to: ids.count, by: AppleMusicLimits.lookupBatchSize) {
            let batch = ids[start..<min(start + AppleMusicLimits.lookupBatchSize, ids.count)]
            let url = AppleMusicEndpoint.lookup.appending(queryItems: [
                URLQueryItem(name: "id", value: batch.joined(separator: ",")),
                URLQueryItem(name: "country", value: country),
            ])
            let response: ITunesResponse = try await get(url)
            tracks += response.results.compactMap(\.track)
        }
        return tracks
    }

    /// The album `track` is from: by catalog ID when the song came from Apple's catalog, otherwise
    /// by matching the artist and title in a search. Nil when nothing matches the artist.
    func album(containing track: Track, country: String) async throws -> Album? {
        let collectionID: Int?
        if let songID = track.catalogSongID {
            let url = AppleMusicEndpoint.lookup.appending(queryItems: [
                URLQueryItem(name: "id", value: songID),
                URLQueryItem(name: "country", value: country),
            ])
            let response: ITunesResponse = try await get(url)
            collectionID = response.results.first?.collectionId
        } else {
            collectionID = try await catalogSong(matching: track, country: country)?.collectionId
        }
        guard let collectionID else { return nil }
        return try await album(id: collectionID, country: country)
    }

    /// The catalog song a YouTube video is, found by its artist and title, preferring the same
    /// title. Nil when no result is by that artist.
    private func catalogSong(matching track: Track, country: String) async throws -> ITunesTrack? {
        let song = SongQuery(track: track)
        let url = AppleMusicEndpoint.search.appending(queryItems: [
            URLQueryItem(name: "term", value: "\(song.artist) \(song.title)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: String(AppleMusicLimits.catalogMatchCandidates)),
            URLQueryItem(name: "country", value: country),
        ])
        let response: ITunesResponse = try await get(url)
        let byArtist = response.results.filter { ($0.artistName ?? "").looselyMatches(song.artist) }
        return byArtist.first { ($0.trackName ?? "").looselyMatches(song.title) } ?? byArtist.first
    }

    func album(id: Int, country: String) async throws -> Album? {
        let url = AppleMusicEndpoint.lookup.appending(queryItems: [
            URLQueryItem(name: "id", value: String(id)),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "country", value: country),
        ])
        let response: ITunesResponse = try await get(url)
        guard let collection = response.results.first(where: { $0.wrapperType == ITunesTrack.collectionWrapper }),
              let title = collection.collectionName, let artist = collection.artistName
        else { return nil }
        let songs = response.results
            .filter { $0.kind == ITunesTrack.songKind }
            .sorted { ($0.discNumber ?? 0, $0.trackNumber ?? 0) < ($1.discNumber ?? 0, $1.trackNumber ?? 0) }
        return Album(
            id: String(id),
            title: title,
            artist: artist,
            artworkURL: AppleArtwork.url(from: collection.artworkUrl100, pixels: AppleMusicLimits.artworkPixels),
            largeArtworkURL: AppleArtwork.url(from: collection.artworkUrl100, pixels: AppleMusicLimits.largeArtworkPixels),
            releaseYear: collection.releaseDate.flatMap { Int($0.prefix(4)) },
            tracks: songs.compactMap(\.track)
        )
    }

    /// The artist of `track` and their most popular songs: by catalog ID when the song came from
    /// Apple's catalog, otherwise by the song's own catalog entry, then by the artist's name.
    /// Nil when no catalog artist matches.
    func artist(of track: Track, country: String) async throws -> Artist? {
        let artistID: Int?
        if let songID = track.catalogSongID {
            let url = AppleMusicEndpoint.lookup.appending(queryItems: [
                URLQueryItem(name: "id", value: songID),
                URLQueryItem(name: "country", value: country),
            ])
            let response: ITunesResponse = try await get(url)
            artistID = response.results.first?.artistId
        } else if let song = try await catalogSong(matching: track, country: country), let id = song.artistId {
            // The song's own credit beats a name search, which can't tell "A & B" from "A".
            artistID = id
        } else {
            let name = SongQuery(track: track).artist
            let url = AppleMusicEndpoint.search.appending(queryItems: [
                URLQueryItem(name: "term", value: name),
                URLQueryItem(name: "entity", value: "musicArtist"),
                URLQueryItem(name: "limit", value: String(AppleMusicLimits.catalogMatchCandidates)),
                URLQueryItem(name: "country", value: country),
            ])
            let response: ITunesResponse = try await get(url)
            let artists = response.results.filter { $0.wrapperType == ITunesTrack.artistWrapper }
            // "Daft Punk" also finds "Daft Punk is Dead", so the exact name wins.
            let exact = artists.first {
                $0.artistName?.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
            artistID = (exact ?? artists.first { ($0.artistName ?? "").looselyMatches(name) })?.artistId
        }
        guard let artistID else { return nil }
        return try await artist(id: artistID, country: country)
    }

    /// The artist's songs and releases, fetched side by side.
    private func artist(id: Int, country: String) async throws -> Artist? {
        async let songLookup: ITunesResponse = get(lookupURL(id: id, entity: "song", limit: AppleMusicLimits.artistSongs, country: country))
        async let releaseLookup: ITunesResponse = get(lookupURL(id: id, entity: "album", limit: AppleMusicLimits.artistReleases, country: country))
        let (songResponse, releaseResponse) = try await (songLookup, releaseLookup)
        guard let profile = songResponse.results.first(where: { $0.wrapperType == ITunesTrack.artistWrapper }),
              let name = profile.artistName
        else { return nil }

        // Hits come back once per album, compilation and reissue they're on; the most popular stays.
        var seenSongs = Set<String>()
        let songs = songResponse.results.compactMap(\.track).filter {
            seenSongs.insert("\($0.artist)|\($0.title)".lowercased()).inserted
        }

        // Releases come most popular first, with explicit and clean copies; the first copy stays.
        var seenReleases = Set<String>()
        let releases = releaseResponse.results.filter { result in
            guard let release = result.albumSummary else { return false }
            return seenReleases.insert("\(release.kind)|\(release.title)".lowercased()).inserted
        }
        let newestFirst: (AlbumSummary, AlbumSummary) -> Bool = {
            ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast)
        }
        let own = releases.filter { $0.artistId == id }.compactMap(\.albumSummary).sorted(by: newestFirst)
        let featured = releases.filter { $0.artistId != id }.compactMap(\.albumSummary).sorted(by: newestFirst)

        return Artist(
            id: String(id),
            name: name,
            genre: profile.primaryGenreName,
            tracks: songs,
            albums: own.filter { $0.kind == .album },
            singles: own.filter { $0.kind == .single },
            appearsOn: featured
        )
    }

    private func lookupURL(id: Int, entity: String, limit: Int, country: String) -> URL {
        AppleMusicEndpoint.lookup.appending(queryItems: [
            URLQueryItem(name: "id", value: String(id)),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "country", value: country),
        ])
    }

    private func get<Response: Decodable>(_ url: URL) async throws -> Response {
        let result: (Data, URLResponse)
        do {
            result = try await session.data(from: url)
        } catch {
            if error.isCancellation { throw error }
            throw AppError(error)
        }
        let (data, response) = result
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? HTTPStatus.success.lowerBound
        guard HTTPStatus.success.contains(statusCode) else {
            throw AppError.server(statusCode: statusCode, message: nil)
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw AppError.decoding
        }
    }
}

nonisolated enum AppleArtwork {
    /// Swaps the `100x100bb` size in an Apple artwork URL for a larger square.
    static func url(from artwork: String?, pixels: Int) -> URL? {
        guard let artwork else { return nil }
        return URL(string: artwork.replacingOccurrences(
            of: AppleMusicLimits.artworkSizeToken,
            with: "\(pixels)x\(pixels)bb"
        ))
    }
}

// MARK: Wire formats

nonisolated struct ITunesResponse: Decodable, Sendable {
    let results: [ITunesTrack]
}

nonisolated struct ITunesTrack: Decodable, Sendable {
    let wrapperType: String?
    let kind: String?
    let trackId: Int?
    let trackName: String?
    let artistName: String?
    let trackTimeMillis: Double?
    let artworkUrl100: String?
    let artistId: Int?
    let primaryGenreName: String?
    let collectionId: Int?
    let collectionName: String?
    let releaseDate: String?
    let discNumber: Int?
    let trackNumber: Int?
    let trackCount: Int?

    static let songKind = "song"
    static let collectionWrapper = "collection"
    static let artistWrapper = "artist"
    /// Apple names singles and EPs "Title - Single" and "Title - EP".
    private static let singleSuffixes = [" - Single", " - EP"]
    /// A lone song released as an "album" is really a single.
    private static let singleSongCount = 1
    private static let millisecondsPerSecond: Double = 1_000

    var track: Track? {
        guard kind == Self.songKind, let trackId, let trackName, let artistName else { return nil }
        return Track(
            id: String(trackId),
            title: trackName,
            artist: artistName,
            artworkURL: AppleArtwork.url(from: artworkUrl100, pixels: AppleMusicLimits.artworkPixels),
            largeArtworkURL: AppleArtwork.url(from: artworkUrl100, pixels: AppleMusicLimits.largeArtworkPixels),
            duration: trackTimeMillis.map { $0 / Self.millisecondsPerSecond },
            source: .appleMusic,
            albumTitle: collectionName,
            releaseYear: releaseYear
        )
    }

    var releaseYear: Int? {
        releaseDate.flatMap { Int($0.prefix(4)) }
    }

    /// An album, single or EP, from an artist lookup.
    var albumSummary: AlbumSummary? {
        guard wrapperType == Self.collectionWrapper, let collectionId, let collectionName else { return nil }
        var title = collectionName
        var kind = trackCount == Self.singleSongCount ? AlbumSummary.Kind.single : .album
        if let suffix = Self.singleSuffixes.first(where: collectionName.hasSuffix) {
            title = String(collectionName.dropLast(suffix.count))
            kind = .single
        }
        return AlbumSummary(
            id: String(collectionId),
            title: title,
            artworkURL: AppleArtwork.url(from: artworkUrl100, pixels: AppleMusicLimits.artworkPixels),
            largeArtworkURL: AppleArtwork.url(from: artworkUrl100, pixels: AppleMusicLimits.largeArtworkPixels),
            releaseDate: releaseDate.flatMap { try? Date($0, strategy: .iso8601) },
            trackCount: trackCount,
            kind: kind
        )
    }
}

/// The iTunes Store's genre charts. Each song sits under `entry`, which is a lone object instead
/// of a list when a chart has only one song, and missing when it has none.
nonisolated struct ITunesGenreChart: Decodable, Sendable {
    let feed: Feed

    struct Feed: Decodable, Sendable {
        let songIDs: [String]

        private enum CodingKeys: String, CodingKey {
            case entry
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let entries = try? container.decode([Entry].self, forKey: .entry) {
                songIDs = entries.map(\.songID)
            } else if let entry = try? container.decode(Entry.self, forKey: .entry) {
                songIDs = [entry.songID]
            } else {
                songIDs = []
            }
        }
    }

    struct Entry: Decodable, Sendable {
        let songID: String

        private enum CodingKeys: String, CodingKey {
            case id
        }

        private struct Identifier: Decodable {
            let attributes: Attributes
        }

        private struct Attributes: Decodable {
            let songID: String

            private enum CodingKeys: String, CodingKey {
                case songID = "im:id"
            }
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            songID = try container.decode(Identifier.self, forKey: .id).attributes.songID
        }
    }
}

nonisolated struct AppleChartResponse: Decodable, Sendable {
    let feed: AppleChartFeed
}

nonisolated struct AppleChartFeed: Decodable, Sendable {
    let results: [AppleChartEntry]
}

nonisolated struct AppleChartEntry: Decodable, Sendable {
    let id: String
    let name: String
    let artistName: String
    let artworkUrl100: String?
}
