import XCTest
@testable import cal_reminder

final class GoogleOAuthConfigTests: XCTestCase {
    func test_make_returnsConfig_forTwoRealValues() {
        let config = GoogleOAuthConfig.make(clientID: "client-id", clientSecret: "client-secret")

        XCTAssertEqual(config?.clientID, "client-id")
        XCTAssertEqual(config?.clientSecret, "client-secret")
    }

    func test_make_nil_whenClientIDMissing() {
        XCTAssertNil(GoogleOAuthConfig.make(clientID: nil, clientSecret: "client-secret"))
    }

    func test_make_nil_whenClientSecretMissing() {
        XCTAssertNil(GoogleOAuthConfig.make(clientID: "client-id", clientSecret: nil))
    }

    func test_make_nil_whenEmpty() {
        XCTAssertNil(GoogleOAuthConfig.make(clientID: "", clientSecret: ""))
    }

    func test_make_nil_whenWhitespaceOnly() {
        XCTAssertNil(GoogleOAuthConfig.make(clientID: "   ", clientSecret: "\n\t"))
    }

    func test_make_nil_forExampleFileValues() {
        XCTAssertNil(GoogleOAuthConfig.make(clientID: "", clientSecret: ""))
    }
}
