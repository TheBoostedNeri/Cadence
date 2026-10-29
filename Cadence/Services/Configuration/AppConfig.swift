import Foundation

/// Values injected at build time: Config/*.xcconfig → Info.plist → here.
nonisolated struct AppConfig: Sendable {
    let youtubeAPIKey: String?
    let googleClientID: String?
    let bundleIdentifier: String

    static func load(from bundle: Bundle = .main) -> AppConfig {
        AppConfig(
            youtubeAPIKey: bundle.configuredString(forInfoKey: InfoKey.youtubeAPIKey),
            googleClientID: bundle.configuredString(forInfoKey: InfoKey.googleClientID),
            bundleIdentifier: bundle.bundleIdentifier ?? Fallback.bundleIdentifier
        )
    }

    /// Google iOS OAuth clients redirect to the reversed client ID,
    /// e.g. `123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc`.
    var googleRedirectScheme: String? {
        googleClientID.map { $0.split(separator: ".").reversed().joined(separator: ".") }
    }

    var googleRedirectURI: String? {
        googleRedirectScheme.map { "\($0):/oauth2redirect" }
    }

    /// Origin the embedded player identifies itself with. YouTube requires embeds to send an
    /// HTTP Referer, so the player page is loaded with a stable URL derived from the bundle ID.
    var playerOrigin: URL? {
        URL(string: "https://\(bundleIdentifier.lowercased())")
    }

    var regionName: String {
        Locale.current.localizedString(forRegionCode: regionCode) ?? regionCode
    }

    /// ISO 3166-1 alpha-2 region used for charts.
    var regionCode: String {
        guard let identifier = Locale.current.region?.identifier,
              identifier.count == Fallback.regionCode.count,
              identifier.allSatisfy(\.isLetter)
        else { return Fallback.regionCode }
        return identifier
    }

    private enum InfoKey {
        static let youtubeAPIKey = "YouTubeAPIKey"
        static let googleClientID = "GoogleClientID"
    }

    private enum Fallback {
        static let bundleIdentifier = "com.example.cadence"
        static let regionCode = "US"
    }
}

private nonisolated extension Bundle {
    func configuredString(forInfoKey key: String) -> String? {
        guard let value = object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // An unresolved build variable such as "$(YOUTUBE_API_KEY)" means it was never set.
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }
}
