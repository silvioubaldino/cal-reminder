import Foundation

/// Google OAuth Desktop-app client credentials (AYD-001 "Google setup"). Loaded from a
/// local JSON file the user creates once after registering the OAuth Client ID — never
/// committed to git, never bundled with the app.
struct GoogleOAuthConfig: Decodable {
    let clientID: String
    let clientSecret: String

    enum CodingKeys: String, CodingKey {
        case clientID = "clientId"
        case clientSecret = "clientSecret"
    }

    static let calendarReadOnlyScope = "https://www.googleapis.com/auth/calendar.readonly"

    enum ConfigError: Error {
        case missingConfigFile(URL)
    }

    static func loadFromDisk(
        fileManager: FileManager = .default,
        url: URL = defaultConfigURL()
    ) throws -> GoogleOAuthConfig {
        guard let data = fileManager.contents(atPath: url.path) else {
            throw ConfigError.missingConfigFile(url)
        }
        return try JSONDecoder().decode(GoogleOAuthConfig.self, from: data)
    }

    static func defaultConfigURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("cal-reminder/google-oauth-config.json")
    }
}
