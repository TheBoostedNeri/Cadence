import Foundation

/// Build settings the app needs from Config/Secrets.xcconfig.
nonisolated enum ConfigurationKey: String, Sendable {
    case youtubeAPIKey = "YOUTUBE_API_KEY"
    case googleClientID = "GOOGLE_CLIENT_ID"
}

nonisolated enum PlaybackFailure: Equatable, Sendable {
    case invalidVideo
    case unavailable
    case embeddingDisabled
    case playerConfiguration
    case playerStopped
    case playerError(code: Int)
    case appleMusicUnavailable
    /// An album song with no YouTube video to play.
    case noYouTubeMatch
    /// A song with no music video to switch to, or a music video with no audio upload.
    case noOtherVersion(wantedVideo: Bool)

    /// Maps IFrame Player API `onError` codes.
    init(youtubeErrorCode code: Int) {
        switch code {
        case YouTubePlayerErrorCode.invalidParameter: self = .invalidVideo
        case YouTubePlayerErrorCode.notFound: self = .unavailable
        case YouTubePlayerErrorCode.embeddingNotAllowed, YouTubePlayerErrorCode.embeddingNotAllowedAlternate:
            self = .embeddingDisabled
        case YouTubePlayerErrorCode.missingClientIdentity: self = .playerConfiguration
        default: self = .playerError(code: code)
        }
    }
}

/// Every failure the UI can present, with user-facing copy.
nonisolated enum AppError: Error, Equatable, Sendable {
    case missingConfiguration(ConfigurationKey)
    case invalidAPIKey
    case apiNotEnabled
    case signInRequired
    case signInCancelled
    case sessionExpired
    case channelRequired
    case offline
    case network(String)
    case quotaExceeded
    case forbidden(String?)
    case notFound
    case server(statusCode: Int, message: String?)
    case decoding
    case authorizationFailed(String)
    case playback(PlaybackFailure)
    case lyricsService(statusCode: Int)
    case appleMusicAccessNeeded
    case appleMusicAccessDenied
    case unsupported(String)
    case unknown(String)

    init(_ error: any Error) {
        if let appError = error as? AppError {
            self = appError
        } else if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                self = .offline
            default:
                self = .network(urlError.localizedDescription)
            }
        } else if error is DecodingError {
            self = .decoding
        } else {
            self = .unknown(error.localizedDescription)
        }
    }

    var title: String {
        switch self {
        case .missingConfiguration(.youtubeAPIKey): String(localized: "Connect to Start Listening")
        case .missingConfiguration(.googleClientID): String(localized: "Account Connection Not Set Up")
        case .invalidAPIKey: String(localized: "Invalid API Key")
        case .apiNotEnabled: String(localized: "YouTube API Not Enabled")
        case .signInRequired: String(localized: "Connect Your Account")
        case .signInCancelled: String(localized: "Sign-In Cancelled")
        case .sessionExpired: String(localized: "Session Expired")
        case .channelRequired: String(localized: "YouTube Channel Needed")
        case .offline: String(localized: "You're Offline")
        case .network: String(localized: "Connection Problem")
        case .quotaExceeded: String(localized: "Daily Limit Reached")
        case .forbidden: String(localized: "Access Denied")
        case .notFound: String(localized: "Not Found")
        case .server: String(localized: "YouTube Error")
        case .decoding: String(localized: "Unexpected Response")
        case .authorizationFailed: String(localized: "Couldn't Connect")
        case .playback(.embeddingDisabled): String(localized: "Can't Play Here")
        case .playback(.unavailable): String(localized: "Video Unavailable")
        case .playback(.invalidVideo): String(localized: "Can't Play This Video")
        case .playback(.playerConfiguration): String(localized: "Player Setup Problem")
        case .playback(.playerStopped): String(localized: "Player Stopped")
        case .playback(.playerError): String(localized: "Playback Error")
        case .playback(.appleMusicUnavailable): String(localized: "Couldn't Play on Apple Music")
        case .playback(.noYouTubeMatch): String(localized: "Not on YouTube")
        case .playback(.noOtherVersion(let wantedVideo)):
            wantedVideo ? String(localized: "No Music Video") : String(localized: "No Song Version")
        case .lyricsService: String(localized: "Lyrics Unavailable")
        case .appleMusicAccessNeeded: String(localized: "Apple Music Access Needed")
        case .appleMusicAccessDenied: String(localized: "Apple Music Access Is Off")
        case .unsupported: String(localized: "Not Available")
        case .unknown: String(localized: "Something Went Wrong")
        }
    }

    var message: String {
        switch self {
        case .missingConfiguration(.youtubeAPIKey):
            String(localized: "Connect your YouTube account, or add a YouTube Data API key (YOUTUBE_API_KEY) to Config/Secrets.xcconfig.")
        case .missingConfiguration(.googleClientID):
            String(localized: "Add an iOS OAuth client ID (GOOGLE_CLIENT_ID) to Config/Secrets.xcconfig to connect a YouTube account.")
        case .invalidAPIKey:
            String(localized: "YouTube rejected the API key. Check YOUTUBE_API_KEY and its iOS app restriction.")
        case .apiNotEnabled:
            String(localized: "Enable YouTube Data API v3 for your Google Cloud project, then try again.")
        case .signInRequired:
            String(localized: "Connect your YouTube account to use your playlists.")
        case .signInCancelled:
            String(localized: "You can connect your account any time from Account.")
        case .sessionExpired:
            String(localized: "Connect your YouTube account again to continue.")
        case .channelRequired:
            String(localized: "This Google account doesn't have a YouTube channel yet. Create one on YouTube to use playlists.")
        case .offline:
            String(localized: "Check your internet connection and try again.")
        case .network(let detail):
            detail
        case .quotaExceeded:
            String(localized: "The app has used its YouTube API quota for today. Try again tomorrow.")
        case .forbidden(let detail):
            detail ?? String(localized: "YouTube didn't allow this request.")
        case .notFound:
            String(localized: "This item no longer exists on YouTube.")
        case .server(let statusCode, let detail):
            detail ?? String(localized: "YouTube returned an error (\(statusCode)). Please try again.")
        case .decoding:
            String(localized: "YouTube sent data this version of the app can't read.")
        case .authorizationFailed(let detail):
            detail
        case .playback(.embeddingDisabled):
            String(localized: "The owner of this video doesn't allow it to play outside YouTube.")
        case .playback(.unavailable):
            String(localized: "This video was removed or made private.")
        case .playback(.invalidVideo):
            String(localized: "This video can't be loaded.")
        case .playback(.playerConfiguration):
            String(localized: "YouTube's player didn't accept this app's identity. Check the bundle identifier and try again.")
        case .playback(.playerStopped):
            String(localized: "The player stopped unexpectedly.")
        case .playback(.playerError(let code)):
            String(localized: "The YouTube player reported error \(code).")
        case .lyricsService(let statusCode):
            String(localized: "The lyrics service returned an error (\(statusCode)). Try again later.")
        case .playback(.appleMusicUnavailable):
            String(localized: "Playing Apple Music songs needs an active Apple Music subscription on this iPhone.")
        case .playback(.noYouTubeMatch):
            String(localized: "Cadence couldn't find a YouTube video of this song.")
        case .playback(.noOtherVersion(let wantedVideo)):
            wantedVideo
                ? String(localized: "Cadence couldn't find a music video of this song on YouTube.")
                : String(localized: "Cadence couldn't find this song's audio on YouTube.")
        case .appleMusicAccessNeeded:
            String(localized: "Allow Cadence to use your Apple Music library.")
        case .appleMusicAccessDenied:
            String(localized: "Turn on Media & Apple Music for Cadence in the Settings app.")
        case .unsupported(let detail):
            detail
        case .unknown(let detail):
            detail
        }
    }

    var systemImage: String {
        switch self {
        case .missingConfiguration(.youtubeAPIKey), .signInRequired, .sessionExpired: "person.crop.circle.badge.exclamationmark"
        case .missingConfiguration, .invalidAPIKey, .apiNotEnabled: "wrench.and.screwdriver"
        case .signInCancelled, .authorizationFailed, .forbidden: "lock.slash"
        case .channelRequired: "person.crop.square.badge.camera"
        case .offline: "wifi.slash"
        case .network: "antenna.radiowaves.left.and.right.slash"
        case .quotaExceeded: "hourglass"
        case .notFound, .playback(.unavailable), .playback(.noYouTubeMatch), .playback(.noOtherVersion):
            "questionmark.square.dashed"
        case .playback: "play.slash"
        case .lyricsService: "quote.bubble"
        case .appleMusicAccessNeeded, .appleMusicAccessDenied: "music.note.house"
        case .unsupported: "nosign"
        case .server, .decoding, .unknown: "exclamationmark.triangle"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .offline, .network, .server, .decoding, .unknown, .apiNotEnabled, .authorizationFailed, .lyricsService,
             .playback(.playerConfiguration), .playback(.playerStopped), .playback(.playerError):
            true
        default:
            false
        }
    }

    /// Errors the user resolves by connecting a YouTube account.
    var offersAccountConnection: Bool {
        switch self {
        case .missingConfiguration(.youtubeAPIKey), .signInRequired, .sessionExpired, .appleMusicAccessNeeded: true
        default: false
        }
    }
}

nonisolated extension Error {
    var isCancellation: Bool {
        self is CancellationError || (self as? URLError)?.code == .cancelled
    }
}
