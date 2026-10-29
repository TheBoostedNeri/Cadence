import Foundation
import Observation

/// Whether the user likes each video, for Now Playing's star. Likes go to the user's YouTube
/// account, so they also show in YouTube's Liked Music and in Cadence's Home.
@Observable
final class YouTubeLikes {
    @ObservationIgnored private let api: YouTubeAPIClient
    @ObservationIgnored private let auth: GoogleAuthService
    /// What YouTube said about each video this launch, so the star asks only once.
    private var likes: [String: Bool] = [:]

    init(api: YouTubeAPIClient, auth: GoogleAuthService) {
        self.api = api
        self.auth = auth
    }

    /// Liking needs a connected account and a YouTube video; Apple Music songs and album songs
    /// still waiting for their video can't be liked.
    func canLike(_ track: Track) -> Bool {
        auth.isSignedIn && track.source == .youtube && !track.needsYouTubeMatch
    }

    func isLiked(_ track: Track) -> Bool {
        likes[track.id] ?? false
    }

    /// Asks YouTube once whether `track` is liked. Costs 1 quota unit; a failure just leaves the
    /// star empty.
    func load(_ track: Track) async {
        guard canLike(track), likes[track.id] == nil else { return }
        if let isLiked = try? await api.isLiked(videoID: track.id) {
            likes[track.id] = isLiked
        }
    }

    /// Shows the change at once and takes it back if YouTube refuses it. Costs 50 quota units.
    func toggle(_ track: Track) async throws {
        let wasLiked = isLiked(track)
        likes[track.id] = !wasLiked
        do {
            try await api.setLiked(!wasLiked, videoID: track.id)
        } catch {
            likes[track.id] = wasLiked
            throw error
        }
    }
}
