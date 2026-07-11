import XCTest
@testable import cal_reminder

final class BannerColorStoreTests: XCTestCase {
    private func makeStore() -> UserDefaultsBannerColorStore {
        let suiteName = "BannerColorStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return UserDefaultsBannerColorStore(defaults: defaults)
    }

    func test_defaultsToPinkWhenUnset() {
        // Arrange
        let store = makeStore()

        // Act
        let color = store.bannerColor

        // Assert
        XCTAssertEqual(color, .pink)
    }

    func test_roundTripsEachPreset() {
        // Arrange
        let store = makeStore()

        for preset in BannerColor.allCases {
            // Act
            store.bannerColor = preset

            // Assert
            XCTAssertEqual(store.bannerColor, preset)
        }
    }

    func test_persistsAcrossStoreInstancesSharingTheSameDefaults() {
        // Arrange
        let suiteName = "BannerColorStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsBannerColorStore(defaults: defaults)

        // Act
        store.bannerColor = .blue
        let relaunchedStore = UserDefaultsBannerColorStore(defaults: defaults)

        // Assert
        XCTAssertEqual(relaunchedStore.bannerColor, .blue)
    }
}
