import CryptoKit
import Foundation

/// Proof Key for Code Exchange (RFC 7636) helpers.
nonisolated enum PKCE {
    private static let randomByteCount = 32

    /// A URL-safe random string, used for the code verifier and the `state` parameter.
    static func makeRandomString() -> String {
        // SystemRandomNumberGenerator is cryptographically secure on Apple platforms.
        let bytes = (0..<randomByteCount).map { _ in UInt8.random(in: .min ... .max) }
        return Data(bytes).base64URLEncodedString()
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

private nonisolated extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
