import Foundation

enum AuthError: Error {
    case notConnected
    case tokenExchangeFailed
    case userInfoFetchFailed
    /// The stored refresh token was rejected by Google (`invalid_grant`) — the session is
    /// dead, not merely unreachable. Thrown after the dead token has already been cleared
    /// from the Keychain (SPEC-010), so callers should move straight to `needsReauth`.
    case refreshTokenRevoked
}

/// The narrow slice of auth the `AccountRegistry` depends on (AYD-007) — deliberately smaller
/// than `AuthManaging`: a future non-OAuth Calendar source (out of scope, see AYD-007 "Open
/// questions") would only ever need to implement this, not `accessToken()`/`authorizedRequest()`.
protocol AccountAuthenticating {
    var isConnected: Bool { get }
    /// Starts the OAuth flow. `loginHint` pre-selects an account in Google's account chooser
    /// (used by "Reconnect" on a specific Account, RF-14) — `nil` lets the user pick freely.
    func connect(loginHint: String?) async throws
    /// Resolves the connected session's `Account` identity (RF-14) — Google's own immutable
    /// account id plus the email shown in the menu bar (RF-06).
    func identity() async throws -> Account
    /// Clears the stored refresh token and cached access token (RF-06 "Sign out").
    func disconnect() async
}

extension AccountAuthenticating {
    /// Starts the OAuth flow letting the user pick freely (no pre-selected account).
    func connect() async throws {
        try await connect(loginHint: nil)
    }
}

protocol AuthManaging: AccountAuthenticating {
    func accessToken() async throws -> String
    /// Builds a request with a fresh access token, sends it, and — on a 401 — refreshes
    /// the access token once and retries transparently (AYD-001 AuthManager contract).
    func authorizedRequest(_ makeRequest: (_ accessToken: String) -> URLRequest) async throws -> (Data, HTTPURLResponse)
}

actor AuthManager: AuthManaging {
    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Double

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private struct UserInfoResponse: Decodable {
        /// Google's own immutable account id — the stable half of `Account.id` (TDR-005).
        let sub: String
        let email: String
    }

    private let config: GoogleOAuthConfig
    private let tokenStore: TokenStoring
    private let httpClient: HTTPClient
    private let authorizationCodeProvider: AuthorizationCodeProviding
    private let clock: () -> Date

    private var cachedAccessToken: String?
    private var cachedAccessTokenExpiry: Date?

    init(
        config: GoogleOAuthConfig,
        tokenStore: TokenStoring,
        httpClient: HTTPClient,
        authorizationCodeProvider: AuthorizationCodeProviding,
        clock: @escaping () -> Date = Date.init
    ) {
        self.config = config
        self.tokenStore = tokenStore
        self.httpClient = httpClient
        self.authorizationCodeProvider = authorizationCodeProvider
        self.clock = clock
    }

    nonisolated var isConnected: Bool {
        tokenStore.refreshToken() != nil
    }

    func connect(loginHint: String?) async throws {
        let verifier = PKCE.generateCodeVerifier()
        let challenge = PKCE.codeChallenge(for: verifier)

        let clientID = config.clientID
        let (code, redirectURI) = try await authorizationCodeProvider.requestAuthorizationCode { redirectURI in
            Self.authorizationURL(clientID: clientID, redirectURI: redirectURI, codeChallenge: challenge, loginHint: loginHint)
        }

        let tokens = try await exchangeCodeForTokens(code: code, verifier: verifier, redirectURI: redirectURI)
        tokenStore.setRefreshToken(tokens.refreshToken)
        cache(tokens)
    }

    func accessToken() async throws -> String {
        if let token = cachedAccessToken, let expiry = cachedAccessTokenExpiry, clock() < expiry {
            return token
        }
        return try await forceRefresh()
    }

    func authorizedRequest(_ makeRequest: (_ accessToken: String) -> URLRequest) async throws -> (Data, HTTPURLResponse) {
        let token = try await accessToken()
        let (data, response) = try await httpClient.send(makeRequest(token))
        guard response.statusCode == 401 else { return (data, response) }

        let refreshedToken = try await forceRefresh()
        return try await httpClient.send(makeRequest(refreshedToken))
    }

    func identity() async throws -> Account {
        let (data, response) = try await authorizedRequest { token in
            var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return request
        }
        guard response.statusCode == 200 else { throw AuthError.userInfoFetchFailed }
        let userInfo = try JSONDecoder().decode(UserInfoResponse.self, from: data)
        return Account(
            id: Account.id(provider: .google, providerUserId: userInfo.sub),
            provider: .google,
            label: userInfo.email
        )
    }

    func disconnect() {
        tokenStore.setRefreshToken(nil)
        cachedAccessToken = nil
        cachedAccessTokenExpiry = nil
    }

    @discardableResult
    private func forceRefresh() async throws -> String {
        guard let refreshToken = tokenStore.refreshToken() else { throw AuthError.notConnected }
        do {
            let tokens = try await refreshAccessToken(refreshToken: refreshToken)
            cache(tokens)
            if let newRefreshToken = tokens.refreshToken, newRefreshToken != refreshToken {
                tokenStore.setRefreshToken(newRefreshToken)
            }
            return tokens.accessToken
        } catch AuthError.refreshTokenRevoked {
            // The session is dead, not merely unreachable: clear the dead token so
            // `isConnected` stops lying about having a usable session (SPEC-010).
            tokenStore.setRefreshToken(nil)
            cachedAccessToken = nil
            cachedAccessTokenExpiry = nil
            throw AuthError.refreshTokenRevoked
        }
    }

    private func cache(_ tokens: TokenResponse) {
        cachedAccessToken = tokens.accessToken
        cachedAccessTokenExpiry = clock().addingTimeInterval(tokens.expiresIn)
    }

    private func exchangeCodeForTokens(code: String, verifier: String, redirectURI: String) async throws -> TokenResponse {
        do {
            return try await requestToken(params: [
                "code": code,
                "client_id": config.clientID,
                "client_secret": config.clientSecret,
                "redirect_uri": redirectURI,
                "grant_type": "authorization_code",
                "code_verifier": verifier
            ])
        } catch is TokenRequestFailure {
            // A rejected authorization code (bad/expired/reused) is a failed exchange, not a
            // dead session — there is no refresh token yet to call "revoked".
            throw AuthError.tokenExchangeFailed
        }
    }

    private func refreshAccessToken(refreshToken: String) async throws -> TokenResponse {
        do {
            return try await requestToken(params: [
                "refresh_token": refreshToken,
                "client_id": config.clientID,
                "client_secret": config.clientSecret,
                "grant_type": "refresh_token"
            ])
        } catch let failure as TokenRequestFailure {
            throw Self.isInvalidGrant(failure.data) ? AuthError.refreshTokenRevoked : AuthError.tokenExchangeFailed
        }
    }

    /// Raw non-200 outcome of a token-endpoint call, before the caller decides what it means
    /// (revoked session vs. a plain failed exchange) — `requestToken` is shared by both the
    /// code exchange and the refresh flow, which interpret the same `invalid_grant` body
    /// differently.
    private struct TokenRequestFailure: Error {
        let status: Int
        let data: Data
    }

    private struct OAuthErrorBody: Decodable {
        let error: String
    }

    private static func isInvalidGrant(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(OAuthErrorBody.self, from: data))?.error == "invalid_grant"
    }

    private func requestToken(params: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(params)

        let (data, response) = try await httpClient.send(request)
        guard response.statusCode == 200 else { throw TokenRequestFailure(status: response.statusCode, data: data) }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    /// `prompt=select_account consent` (was `consent` alone): without `select_account`, Google
    /// silently reuses the browser's existing session cookie and never offers a chooser, which
    /// would make it impossible to add a *second* Google Account (RF-14). `loginHint` further
    /// pre-selects an account — used by "Reconnect" on a specific Account.
    private static func authorizationURL(clientID: String, redirectURI: String, codeChallenge: String, loginHint: String?) -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        var queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(
                name: "scope",
                value: "\(GoogleOAuthConfig.calendarReadOnlyScope) \(GoogleOAuthConfig.userInfoEmailScope)"
            ),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "select_account consent")
        ]
        if let loginHint {
            queryItems.append(URLQueryItem(name: "login_hint", value: loginHint))
        }
        components.queryItems = queryItems
        return components.url!
    }

    private static let formValueAllowedCharacters: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private static func formEncode(_ params: [String: String]) -> Data {
        let pairs = params.map { key, value -> String in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: formValueAllowedCharacters) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: formValueAllowedCharacters) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }
}
