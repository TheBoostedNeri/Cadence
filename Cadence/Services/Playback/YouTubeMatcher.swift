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
