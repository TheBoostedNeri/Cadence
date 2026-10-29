import Foundation

/// Finds the YouTube video for each album song. Albums come from Apple's catalog, and every new
/// match costs a YouTube search (about 100 quota units), so each song is searched for only once
/// on this device.
final class YouTubeMatcher {
    private let api: YouTubeAPIClient
    private let defaults: UserDefaults
    /// Video IDs by Apple catalog song ID.
    private var videoIDs: [String: String]

    init(api: YouTubeAPIClient, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        videoIDs = defaults.dictionary(forKey: StorageKey.youtubeMatches) as? [String: String] ?? [:]
    }

    /// `track` as its YouTube video. Throws `noYouTubeMatch` when YouTube has no video for it.
    func match(_ track: Track) async throws -> Track {
        let songID = track.catalogSongID ?? track.id
        if let videoID = videoIDs[songID] {
            return track.matched(toVideo: videoID)
        }
        guard let videoID = try await api.videoID(matching: track) else {
            throw AppError.playback(.noYouTubeMatch)
        }
        videoIDs[songID] = videoID
        defaults.set(videoIDs, forKey: StorageKey.youtubeMatches)
        return track.matched(toVideo: videoID)
    }
}

/// Finds the other version of a YouTube song for Now Playing's Song and Video switch: the music
/// video of a song playing as audio, or the audio of a music video. Each new lookup costs a
/// YouTube search (about 100 quota units), so answers, including songs that have no other
/// version, are kept on this device both ways round.
final class SongVersions {
    private let api: YouTubeAPIClient
    private let defaults: UserDefaults
    /// The other version's video ID by `key(_:wantsVideo:)`; empty when YouTube has none.
    private var versionIDs: [String: String]

    init(api: YouTubeAPIClient, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        versionIDs = defaults.dictionary(forKey: StorageKey.songVersions) as? [String: String] ?? [:]
    }

    /// `track` as its music video, or as its audio. Throws `noOtherVersion` when YouTube has none.
    func otherVersion(of track: Track, wantsVideo: Bool) async throws -> Track {
        let key = Self.key(track.id, wantsVideo: wantsVideo)
        let videoID: String
        if let known = versionIDs[key] {
            videoID = known
        } else {
            videoID = try await api.otherVersionID(of: track, wantsVideo: wantsVideo) ?? ""
            versionIDs[key] = videoID
            if !videoID.isEmpty {
                versionIDs[Self.key(videoID, wantsVideo: !wantsVideo)] = track.id
            }
            defaults.set(versionIDs, forKey: StorageKey.songVersions)
        }
        guard !videoID.isEmpty, let version = try await api.videos(ids: [videoID]).first else {
            throw AppError.playback(.noOtherVersion(wantedVideo: wantsVideo))
        }
        // An album song keeps Apple's title and artwork, as its first video did.
        guard track.appleCatalogID != nil else { return version }
        var matched = track.matched(toVideo: version.id)
        matched.videoKind = version.videoKind
        return matched
    }

    private static func key(_ videoID: String, wantsVideo: Bool) -> String {
        "\(videoID)>\(wantsVideo ? "video" : "song")"
    }
}
