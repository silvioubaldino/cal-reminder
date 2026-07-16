import XCTest
@testable import cal_reminder

private final class FakeTokenStore: TokenStoring {
    private var token: String?

    init(initialToken: String? = nil) {
        self.token = initialToken
    }

    func refreshToken() -> String? { token }
    func setRefreshToken(_ token: String?) { self.token = token }
}

private final class StubAuthorizationCodeProvider: AuthorizationCodeProviding {
    let code: String

    init(code: String = "auth-code-123") {
        self.code = code
    }

    func requestAuthorizationCode(
        buildAuthorizationURL: @escaping (String) -> URL
    ) async throws -> (code: String, redirectURI: String) {
        let redirectURI = "http://127.0.0.1:12345/"
        _ = buildAuthorizationURL(redirectURI)
        return (code, redirectURI)
    }
}

/// Records requests and replays queued responses in order, so tests can script a
/// sequence like "401, then 200 on retry" without a real network.
private actor StubHTTPClient: HTTPClient {
    private var responses: [(Data, HTTPURLResponse)]
    private(set) var sentRequests: [URLRequest] = []

    init(responses: [(Data, HTTPURLResponse)]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        sentRequests.append(request)
        guard !responses.isEmpty else {
            fatalError("StubHTTPClient ran out of scripted responses")
        }
        return responses.removeFirst()
    }
}

private func httpResponse(status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://oauth2.googleapis.com/token")!, statusCode: status, httpVersion: nil, headerFields: nil)!
}

private func tokenResponseData(accessToken: String, refreshToken: String? = nil, expiresIn: Double = 3600) -> Data {
    var json: [String: Any] = ["access_token": accessToken, "expires_in": expiresIn]
    if let refreshToken { json["refresh_token"] = refreshToken }
    return try! JSONSerialization.data(withJSONObject: json)
}

final class AuthManagerTests: XCTestCase {
    private let config = GoogleOAuthConfig(clientID: "client-id", clientSecret: "client-secret")

    func test_isConnected_falseWithoutRefreshToken() {
        // Arrange
        let manager = AuthManager(
            config: config,
            tokenStore: FakeTokenStore(),
            httpClient: StubHTTPClient(responses: []),
            authorizationCodeProvider: StubAuthorizationCodeProvider()
        )

        // Act / Assert
        XCTAssertFalse(manager.isConnected)
    }

    func test_connect_storesRefreshTokenAndConnects() async throws {
        // Arrange
        let tokenStore = FakeTokenStore()
        let httpClient = StubHTTPClient(responses: [
            (tokenResponseData(accessToken: "access-1", refreshToken: "refresh-1"), httpResponse(status: 200))
        ])
        let manager = AuthManager(
            config: config,
            tokenStore: tokenStore,
            httpClient: httpClient,
            authorizationCodeProvider: StubAuthorizationCodeProvider()
        )

        // Act
        try await manager.connect()

        // Assert
        XCTAssertEqual(tokenStore.refreshToken(), "refresh-1")
        XCTAssertTrue(manager.isConnected)
    }

    func test_accessToken_reusesCachedTokenUntilExpiry() async throws {
        // Arrange
        var now = Date(timeIntervalSince1970: 0)
        let httpClient = StubHTTPClient(responses: [
            (tokenResponseData(accessToken: "access-1", expiresIn: 3600), httpResponse(status: 200))
        ])
        let manager = AuthManager(
            config: config,
            tokenStore: FakeTokenStore(initialToken: "refresh-1"),
            httpClient: httpClient,
            authorizationCodeProvider: StubAuthorizationCodeProvider(),
            clock: { now }
        )

        // Act
        let first = try await manager.accessToken()
        now = now.addingTimeInterval(60) // still well within the 3600s expiry
        let second = try await manager.accessToken()

        // Assert
        XCTAssertEqual(first, "access-1")
        XCTAssertEqual(second, "access-1")
        let requestCount = await httpClient.sentRequests.count
        XCTAssertEqual(requestCount, 1, "should not refresh again before expiry")
    }

    func test_accessToken_refreshesWhenExpired() async throws {
        // Arrange
        var now = Date(timeIntervalSince1970: 0)
        let httpClient = StubHTTPClient(responses: [
            (tokenResponseData(accessToken: "access-1", expiresIn: 60), httpResponse(status: 200)),
            (tokenResponseData(accessToken: "access-2", expiresIn: 60), httpResponse(status: 200))
        ])
        let manager = AuthManager(
            config: config,
            tokenStore: FakeTokenStore(initialToken: "refresh-1"),
            httpClient: httpClient,
            authorizationCodeProvider: StubAuthorizationCodeProvider(),
            clock: { now }
        )

        // Act
        _ = try await manager.accessToken()
        now = now.addingTimeInterval(120) // past expiry
        let refreshed = try await manager.accessToken()

        // Assert
        XCTAssertEqual(refreshed, "access-2")
    }

    func test_authorizedRequest_refreshesAndRetriesOnceOn401() async throws {
        // Arrange
        let httpClient = StubHTTPClient(responses: [
            (tokenResponseData(accessToken: "access-1", expiresIn: 3600), httpResponse(status: 200)), // initial accessToken()
            (Data(), httpResponse(status: 401)), // first attempt with access-1
            (tokenResponseData(accessToken: "access-2", expiresIn: 3600), httpResponse(status: 200)), // forced refresh
            ("success".data(using: .utf8)!, httpResponse(status: 200)) // retry with access-2
        ])
        let manager = AuthManager(
            config: config,
            tokenStore: FakeTokenStore(initialToken: "refresh-1"),
            httpClient: httpClient,
            authorizationCodeProvider: StubAuthorizationCodeProvider()
        )

        // Act
        let (data, response) = try await manager.authorizedRequest { token in
            URLRequest(url: URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary")!)
        }

        // Assert
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), "success")
    }

    func test_userEmail_returnsEmailFromUserInfoEndpoint() async throws {
        // Arrange
        let httpClient = StubHTTPClient(responses: [
            (tokenResponseData(accessToken: "access-1", expiresIn: 3600), httpResponse(status: 200)), // accessToken()
            (try! JSONSerialization.data(withJSONObject: ["email": "user@example.com"]), httpResponse(status: 200)) // userinfo
        ])
        let manager = AuthManager(
            config: config,
            tokenStore: FakeTokenStore(initialToken: "refresh-1"),
            httpClient: httpClient,
            authorizationCodeProvider: StubAuthorizationCodeProvider()
        )

        // Act
        let email = try await manager.userEmail()

        // Assert
        XCTAssertEqual(email, "user@example.com")
    }

    func test_connect_tokenExchangeCarriesClientCredentialsAndPKCE() async throws {
        // Arrange
        let httpClient = StubHTTPClient(responses: [
            (tokenResponseData(accessToken: "access-1", refreshToken: "refresh-1"), httpResponse(status: 200))
        ])
        let manager = AuthManager(
            config: config,
            tokenStore: FakeTokenStore(),
            httpClient: httpClient,
            authorizationCodeProvider: StubAuthorizationCodeProvider()
        )

        // Act
        try await manager.connect()

        // Assert
        let sentRequests = await httpClient.sentRequests
        let body = String(data: sentRequests[0].httpBody ?? Data(), encoding: .utf8) ?? ""
        // Google's installed-app token endpoint requires client_secret alongside PKCE (TDR-002).
        XCTAssertTrue(body.contains("client_secret=client-secret"), "Google requires client_secret on the exchange")
        XCTAssertTrue(body.contains("code_verifier="), "PKCE code_verifier must also be present")
        XCTAssertTrue(body.contains("client_id=client-id"))
    }

    func test_accessToken_throwsWhenNeverConnected() async {
        // Arrange
        let manager = AuthManager(
            config: config,
            tokenStore: FakeTokenStore(),
            httpClient: StubHTTPClient(responses: []),
            authorizationCodeProvider: StubAuthorizationCodeProvider()
        )

        // Act / Assert
        do {
            _ = try await manager.accessToken()
            XCTFail("expected notConnected to be thrown")
        } catch AuthError.notConnected {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
