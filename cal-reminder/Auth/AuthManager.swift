import Foundation

enum AuthError: Error {
    case notConnected
    case tokenExchangeFailed
    case userInfoFetchFailed
}

protocol AuthManaging {
    var isConnected: Bool { get }
    func connect() async throws
    func accessToken() async throws -> String
    /// Builds a request with a fresh access token, sends it, and — on a 401 — refreshes
    /// the access token once and retries transparently (AYD-001 AuthManager contract).
    func authorizedRequest(_ makeRequest: (_ accessToken: String) -> URLRequest) async throws -> (Data, HTTPURLResponse)
    /// The connected Google account's email address, shown in the menu bar (RF-06).
    func userEmail() async throws -> String
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

    func connect() async throws {
        let verifier = PKCE.generateCodeVerifier()
        let challenge = PKCE.codeChallenge(for: verifier)

        let clientID = config.clientID
        let (code, redirectURI) = try await authorizationCodeProvider.requestAuthorizationCode { redirectURI in
            Self.authorizationURL(clientID: clientID, redirectURI: redirectURI, codeChallenge: challenge)
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

    func userEmail() async throws -> String {
        let (data, response) = try await authorizedRequest { token in
            var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return request
        }
        guard response.statusCode == 200 else { throw AuthError.userInfoFetchFailed }
        return try JSONDecoder().decode(UserInfoResponse.self, from: data).email
    }

    @discardableResult
    private func forceRefresh() async throws -> String {
        guard let refreshToken = tokenStore.refreshToken() else { throw AuthError.notConnected }
        let tokens = try await refreshAccessToken(refreshToken: refreshToken)
        cache(tokens)
        if let newRefreshToken = tokens.refreshToken, newRefreshToken != refreshToken {
            tokenStore.setRefreshToken(newRefreshToken)
        }
        return tokens.accessToken
    }

    private func cache(_ tokens: TokenResponse) {
        cachedAccessToken = tokens.accessToken
        cachedAccessTokenExpiry = clock().addingTimeInterval(tokens.expiresIn)
    }

    private func exchangeCodeForTokens(code: String, verifier: String, redirectURI: String) async throws -> TokenResponse {
        try await requestToken(params: [
            "code": code,
            "client_id": config.clientID,
            "client_secret": config.clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier
        ])
    }

    private func refreshAccessToken(refreshToken: String) async throws -> TokenResponse {
        try await requestToken(params: [
            "refresh_token": refreshToken,
            "client_id": config.clientID,
            "client_secret": config.clientSecret,
            "grant_type": "refresh_token"
        ])
    }

    private func requestToken(params: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(params)

        let (data, response) = try await httpClient.send(request)
        guard response.statusCode == 200 else { throw AuthError.tokenExchangeFailed }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private static func authorizationURL(clientID: String, redirectURI: String, codeChallenge: String) -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
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
            URLQueryItem(name: "prompt", value: "consent")
        ]
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
