import Foundation

/// Google OAuth Desktop-app (installed-app) client identity (AYD-003). Google's token
/// endpoint requires **both** `client_id` and `client_secret` on the code exchange and
/// refresh — even for installed apps, where Google explicitly documents that the secret
/// "is obviously not treated as a secret." PKCE (`code_verifier`, see `AuthManager`) is an
/// additional protection, not a replacement for the secret. Both are injected at build time
/// from `Config/Secrets.xcconfig` into the bundle's `Info.plist` (TDR-007, supersedes TDR-003):
/// a Distributed Build carries the project's own credentials, a Source Build the builder's.
struct GoogleOAuthConfig {
    let clientID: String
    let clientSecret: String

    static let calendarReadOnlyScope = "https://www.googleapis.com/auth/calendar.readonly"
    static let userInfoEmailScope = "https://www.googleapis.com/auth/userinfo.email"

    /// `nil` when either value is missing, empty, or whitespace-only — which is what the
    /// tracked `Secrets.example.xcconfig` contains, so a never-configured clone is
    /// unconfigured (SPEC-018) rather than failing with an empty client id.
    static func make(clientID: String?, clientSecret: String?) -> GoogleOAuthConfig? {
        guard
            let clientID = clientID?.trimmingCharacters(in: .whitespacesAndNewlines), !clientID.isEmpty,
            let clientSecret = clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines), !clientSecret.isEmpty
        else {
            return nil
        }
        return GoogleOAuthConfig(clientID: clientID, clientSecret: clientSecret)
    }

    /// The app's bundled OAuth client credentials, read from `Info.plist` (TDR-007).
    static let bundled: GoogleOAuthConfig? = make(
        clientID: Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String,
        clientSecret: Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientSecret") as? String
    )
}
