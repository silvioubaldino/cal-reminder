import XCTest
@testable import cal_reminder

final class UpdateSettingsStoreTests: XCTestCase {
    private func makeStore() -> UserDefaultsUpdateSettingsStore {
        let suiteName = "UpdateSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return UserDefaultsUpdateSettingsStore(defaults: defaults)
    }

    func test_defaultsToFalseWhenUnset() {
        // Arrange
        let store = makeStore()

        // Act
        let automaticallyChecks = store.automaticallyChecks

        // Assert
        XCTAssertFalse(automaticallyChecks)
    }

    func test_roundTripsBothValues() {
        // Arrange
        let store = makeStore()

        for value in [true, false] {
            // Act
            store.automaticallyChecks = value

            // Assert
            XCTAssertEqual(store.automaticallyChecks, value)
        }
    }

    func test_persistsAcrossStoreInstancesSharingTheSameDefaults() {
        // Arrange
        let suiteName = "UpdateSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsUpdateSettingsStore(defaults: defaults)

        // Act
        store.automaticallyChecks = true
        let relaunchedStore = UserDefaultsUpdateSettingsStore(defaults: defaults)

        // Assert
        XCTAssertTrue(relaunchedStore.automaticallyChecks)
    }
}
