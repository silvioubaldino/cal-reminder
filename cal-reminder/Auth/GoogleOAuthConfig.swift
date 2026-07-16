import Foundation

/// Google OAuth Desktop-app (installed-app) client identity (AYD-003). Google's token
/// endpoint requires **both** `client_id` and `client_secret` on the code exchange and
/// refresh — even for installed apps, where Google explicitly documents that the secret
/// "is obviously not treated as a secret." PKCE (`code_verifier`, see `AuthManager`) is an
/// additional protection, not a replacement for the secret. Both therefore ship embedded in
/// the binary; there is no per-user setup file (supersedes TDR-001, see TDR-002).
struct GoogleOAuthConfig {
    let clientID: String
    let clientSecret: String

    static let calendarReadOnlyScope = "https://www.googleapis.com/auth/calendar.readonly"
    static let userInfoEmailScope = "https://www.googleapis.com/auth/userinfo.email"

    /// The app's embedded OAuth client credentials, from Google Cloud Console (TDR-002).
    static let embedded = GoogleOAuthConfig(
        clientID: "396336320209-1bng3bve52km46jrh5tdq5gfv1lmal4n.apps.googleusercontent.com",
        clientSecret: "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"
    )
}
