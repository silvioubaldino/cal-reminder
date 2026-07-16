import Foundation

/// Google OAuth Desktop-app **public client** identity (AYD-003). Google does not treat an
/// installed-app Client ID as confidential — PKCE (`code_verifier`, see `AuthManager`) is
/// what proves the token exchange came from this app, not a secret. The Client ID therefore
/// ships embedded in the binary; there is no per-user setup file (supersedes TDR-001, see
/// TDR-002).
struct GoogleOAuthConfig {
    let clientID: String

    static let calendarReadOnlyScope = "https://www.googleapis.com/auth/calendar.readonly"
    static let userInfoEmailScope = "https://www.googleapis.com/auth/userinfo.email"

    /// The app's embedded OAuth Client ID. Replace with the real value from Google Cloud
    /// Console before distributing a signed build (TDR-002); empty until then.
    static let embedded = GoogleOAuthConfig(clientID: "")
}
