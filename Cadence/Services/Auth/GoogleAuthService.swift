import AuthenticationServices
import Foundation
import Observation
import SwiftUI

/// Google OAuth 2.0 for installed apps: authorization code flow with PKCE, run in the system
/// web authentication sheet. Tokens live in the Keychain.
@Observable
final class GoogleAuthService {
    private(set) var isSignedIn: Bool

    var isConfigured: Bool { config.googleClientID != nil }

    @ObservationIgnored private let config: AppConfig
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored private var tokens: OAuthTokens?
    @ObservationIgnored private var refreshTask: Task<OAuthTokens, any Error>?

    init(config: AppConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
        keychain = KeychainStore(service: config.bundleIdentifier)
        let storedTokens = keychain.data(for: KeychainAccount.googleTokens)
            .flatMap { try? JSONDecoder().decode(OAuthTokens.self, from: $0) }
        tokens = storedTokens
        isSignedIn = storedTokens != nil
    }

    // MARK: Sign in / out

    func signIn(using webAuthenticationSession: WebAuthenticationSession) async throws {
        guard let clientID = config.googleClientID,
              let scheme = config.googleRedirectScheme,
              let redirectURI = config.googleRedirectURI
        else { throw AppError.missingConfiguration(.googleClientID) }

        let verifier = PKCE.makeRandomString()
        let state = PKCE.makeRandomString()
        let authorizationURL = GoogleEndpoint.authorize.appending(queryItems: [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleScope.youtube),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ])

        let callbackURL: URL
        do {
            callbackURL = try await webAuthenticationSession.authenticate(
                using: authorizationURL,
                callback: .customScheme(scheme),
                preferredBrowserSession: nil,
                additionalHeaderFields: [:]
            )
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            throw AppError.signInCancelled
        } catch {
            throw AppError.authorizationFailed(error.localizedDescription)
        }

        let parameters = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func parameter(_ name: String) -> String? {
            parameters.first { $0.name == name }?.value
        }
        if let error = parameter("error") {
            throw error == "access_denied" ? AppError.signInCancelled : AppError.authorizationFailed(error)
        }
        guard parameter("state") == state, let code = parameter("code") else {
            throw AppError.authorizationFailed(String(localized: "The sign-in response couldn't be verified."))
        }

        let response = try await requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
        ])
        guard let refreshToken = response.refreshToken else {
            throw AppError.authorizationFailed(String(localized: "Google didn't grant offline access."))
        }
        store(OAuthTokens(response: response, refreshToken: refreshToken))
    }

    func signOut() async {
        let refreshToken = tokens?.refreshToken
        clearSession()
        guard let refreshToken else { return }
        // Best effort: revoking also removes the app from the user's Google account permissions.
        var request = URLRequest(url: GoogleEndpoint.revoke)
        request.httpMethod = "POST"
        request.setValue(FormEncoding.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = FormEncoding.encode(["token": refreshToken])
        _ = try? await session.data(for: request)
    }

    // MARK: Tokens

    /// A non-expired access token, refreshing if needed, or nil when no account is connected.
    func validAccessToken() async throws -> String? {
        guard let tokens else { return nil }
        if tokens.expiresAt > .now { return tokens.accessToken }
        return try await refreshedTokens().accessToken
    }

    func refreshAccessToken() async throws {
        _ = try await refreshedTokens()
    }

    /// Coalesces concurrent refreshes into a single token request.
    private func refreshedTokens() async throws -> OAuthTokens {
        if let refreshTask { return try await refreshTask.value }
        let task = Task { try await performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> OAuthTokens {
        guard let current = tokens, let clientID = config.googleClientID else {
            throw AppError.signInRequired
        }
        do {
            let response = try await requestToken([
                "grant_type": "refresh_token",
                "refresh_token": current.refreshToken,
                "client_id": clientID,
            ])
            let refreshed = OAuthTokens(response: response, refreshToken: response.refreshToken ?? current.refreshToken)
            store(refreshed)
            return refreshed
        } catch AppError.sessionExpired {
            clearSession()
            throw AppError.sessionExpired
        }
    }

    private func requestToken(_ parameters: [String: String]) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: GoogleEndpoint.token)
        request.httpMethod = "POST"
        request.setValue(FormEncoding.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = FormEncoding.encode(parameters)

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            throw AppError(error)
        }
        let (data, response) = result
        let decoder = JSONDecoder()
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? HTTPStatus.success.lowerBound
        guard HTTPStatus.success.contains(statusCode) else {
            let oauthError = try? decoder.decode(OAuthErrorResponse.self, from: data)
            if oauthError?.error == OAuthErrorResponse.invalidGrant {
                throw AppError.sessionExpired
            }
            throw AppError.authorizationFailed(
                oauthError?.errorDescription ?? oauthError?.error
                    ?? String(localized: "Google returned status \(statusCode).")
            )
        }
        do {
            return try decoder.decode(OAuthTokenResponse.self, from: data)
        } catch {
            throw AppError.decoding
        }
    }

    private func store(_ newTokens: OAuthTokens) {
        tokens = newTokens
        isSignedIn = true
        // If the Keychain write fails the session still works until the app quits.
        if let data = try? JSONEncoder().encode(newTokens) {
            try? keychain.set(data, for: KeychainAccount.googleTokens)
        }
    }

    private func clearSession() {
        tokens = nil
        isSignedIn = false
        keychain.removeValue(for: KeychainAccount.googleTokens)
    }
}

private enum KeychainAccount {
    static let googleTokens = "google.oauth.tokens"
}

nonisolated struct OAuthTokens: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    init(response: OAuthTokenResponse, refreshToken: String, now: Date = .now) {
        accessToken = response.accessToken
        self.refreshToken = refreshToken
        expiresAt = now.addingTimeInterval(response.expiresIn - OAuthPolicy.expiryLeeway)
    }
}

nonisolated struct OAuthTokenResponse: Decodable, Sendable {
    let accessToken: String
    let expiresIn: TimeInterval
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

nonisolated struct OAuthErrorResponse: Decodable, Sendable {
    static let invalidGrant = "invalid_grant"

    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

nonisolated enum FormEncoding {
    static let contentType = "application/x-www-form-urlencoded"
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    static func encode(_ parameters: [String: String]) -> Data {
        let body = parameters
            .sorted { $0.key < $1.key }
            .map { "\(escape($0.key))=\(escape($0.value))" }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}
