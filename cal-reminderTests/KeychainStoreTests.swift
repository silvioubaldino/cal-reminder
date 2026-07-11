import XCTest
@testable import cal_reminder

final class KeychainStoreTests: XCTestCase {
    private func makeStore() -> KeychainStore {
        KeychainStore(service: "com.cal-reminder.auth.tests.\(UUID().uuidString)")
    }

    func test_returnsNilWhenNeverSet() {
        // Arrange
        let store = makeStore()

        // Act
        let token = store.refreshToken()

        // Assert
        XCTAssertNil(token)
    }

    func test_roundTripsAToken() {
        // Arrange
        let store = makeStore()

        // Act
        store.setRefreshToken("refresh-token-value")

        // Assert
        XCTAssertEqual(store.refreshToken(), "refresh-token-value")
    }

    func test_overwritesAPreviouslyStoredToken() {
        // Arrange
        let store = makeStore()
        store.setRefreshToken("first-token")

        // Act
        store.setRefreshToken("second-token")

        // Assert
        XCTAssertEqual(store.refreshToken(), "second-token")
    }

    func test_settingNilDeletesTheToken() {
        // Arrange
        let store = makeStore()
        store.setRefreshToken("some-token")

        // Act
        store.setRefreshToken(nil)

        // Assert
        XCTAssertNil(store.refreshToken())
    }
}
