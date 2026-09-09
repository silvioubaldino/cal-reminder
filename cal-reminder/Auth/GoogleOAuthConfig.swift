import Foundation

/// Google OAuth Desktop-app (installed-app) client identity (AYD-003). Google's token
/// endpoint requires **both** `client_id` and `client_secret` on the code exchange and
/// refresh — even for installed apps, where Google explicitly documents that the secret
/// "is obviously not treated as a secret." PKCE (`code_verifier`, see `AuthManager`) is an
/// additional protection, not a replacement for the secret. Both are injected at build time
/// into the bundle's `Info.plist` (TDR-007, supersedes TDR-003).
struct GoogleOAuthConfig {
    let clientID: String
    let clientSecret: String

    static let calendarReadOnlyScope = "https://www.googleapis.com/auth/calendar.readonly"
    static let userInfoEmailScope = "https://www.googleapis.com/auth/userinfo.email"

    static func make(clientID: String?, clientSecret: String?) -> GoogleOAuthConfig? {
        guard
            let clientID = clientID?.trimmingCharacters(in: .whitespacesAndNewlines), !clientID.isEmpty,
            let clientSecret = clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines), !clientSecret.isEmpty
        else {
            return nil
        }
        return GoogleOAuthConfig(clientID: clientID, clientSecret: clientSecret)
    }

    static let bundled: GoogleOAuthConfig? = make(
        clientID: Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String,
        clientSecret: Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientSecret") as? String
    )
}
