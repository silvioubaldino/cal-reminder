import XCTest
@testable import cal_reminder

final class CalendarSelectionStoreTests: XCTestCase {
    private func makeStore() -> UserDefaultsCalendarSelectionStore {
        let suiteName = "CalendarSelectionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return UserDefaultsCalendarSelectionStore(defaults: defaults)
    }

    func test_defaultsToNilWhenUnset() {
        // Arrange
        let store = makeStore()

        // Act / Assert
        XCTAssertNil(store.selectedCalendarIds)
    }

    func test_nilSelectionIsEffectivelyAllCalendars() {
        // Arrange (RF-10 default: never chosen → all)
        let store = makeStore()
        let allIds: Set<String> = ["A", "B", "C"]

        // Act / Assert
        for id in allIds {
            XCTAssertTrue(store.isSelected(id, within: allIds))
        }
    }

    func test_deselectingOneKeepsOthersEffectivelySelected() {
        // Arrange
        let store = makeStore()
        let allIds: Set<String> = ["A", "B", "C"]

        // Act
        store.setSelected("B", false, within: allIds)

        // Assert
        XCTAssertEqual(store.selectedCalendarIds, ["A", "C"])
        XCTAssertTrue(store.isSelected("A", within: allIds))
        XCTAssertFalse(store.isSelected("B", within: allIds))
        XCTAssertTrue(store.isSelected("C", within: allIds))
    }

    func test_reselectingAfterDeselectRestoresIt() {
        // Arrange
        let store = makeStore()
        let allIds: Set<String> = ["A", "B"]
        store.setSelected("B", false, within: allIds)

        // Act
        store.setSelected("B", true, within: allIds)

        // Assert
        XCTAssertTrue(store.isSelected("B", within: allIds))
    }

    func test_persistsAcrossStoreInstancesSharingTheSameDefaults() {
        // Arrange
        let suiteName = "CalendarSelectionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = UserDefaultsCalendarSelectionStore(defaults: defaults)

        // Act
        store.setSelected("B", false, within: ["A", "B", "C"])
        let relaunchedStore = UserDefaultsCalendarSelectionStore(defaults: defaults)

        // Assert
        XCTAssertEqual(relaunchedStore.selectedCalendarIds, ["A", "C"])
    }

    func test_staleStoredIdIsIntersectedOutByCaller() {
        // Arrange: a Calendar removed/unshared since the selection was stored.
        let store = makeStore()
        store.setSelected("removed", true, within: ["removed"])

        // Act
        let effective = store.selectedCalendarIds?.intersection(["A", "B"]) ?? ["A", "B"]

        // Assert
        XCTAssertTrue(effective.isEmpty)
    }
}
