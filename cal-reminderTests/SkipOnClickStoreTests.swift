import XCTest
@testable import cal_reminder

final class SkipOnClickStoreTests: XCTestCase {
    private func makeStore() -> UserDefaultsSkipOnClickStore {
        let suiteName = "SkipOnClickStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return UserDefaultsSkipOnClickStore(defaults: defaults)
    }

    func test_defaultsToTrueWhenUnset() {
        // Arrange
        let store = makeStore()

        // Act
        let skipOnClick = store.skipOnClick

        // Assert
        XCTAssertTrue(skipOnClick)
    }

    func test_roundTripsBothValues() {
        // Arrange
        let store = makeStore()

        for value in [true, false] {
            // Act
            store.skipOnClick = value

            // Assert
            XCTAssertEqual(store.skipOnClick, value)
        }
    }

    func test_persistsAcrossStoreInstancesSharingTheSameDefaults() {
        // Arrange
        let suiteName = "SkipOnClickStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsSkipOnClickStore(defaults: defaults)

        // Act
        store.skipOnClick = false
        let relaunchedStore = UserDefaultsSkipOnClickStore(defaults: defaults)

        // Assert
        XCTAssertFalse(relaunchedStore.skipOnClick)
    }
}
