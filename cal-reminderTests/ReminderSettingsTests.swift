import XCTest
@testable import cal_reminder

final class ReminderSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "ReminderSettingsTests"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_defaultsReproduceTheBehaviorBeforeExtraReminders() {
        // Arrange + Act
        let settings = ReminderSettings.default

        // Assert
        XCTAssertTrue(settings.inheritEventReminders)
        XCTAssertTrue(settings.extraMinutes.isEmpty)
        XCTAssertFalse(settings.isSilent)
    }

    func test_nothingStoredYetReadsAsTheDefaults() {
        // Arrange
        let store = UserDefaultsReminderSettingsStore(defaults: defaults)

        // Act
        let settings = store.settings

        // Assert
        XCTAssertEqual(settings, .default)
    }

    func test_selectionSurvivesARestart() {
        // Arrange
        let store = UserDefaultsReminderSettingsStore(defaults: defaults)
        store.settings = ReminderSettings(inheritEventReminders: false, extraMinutes: [1, 15])

        // Act — a fresh store over the same defaults is what a restart sees
        let restarted = UserDefaultsReminderSettingsStore(defaults: defaults)

        // Assert
        XCTAssertEqual(restarted.settings, ReminderSettings(inheritEventReminders: false, extraMinutes: [1, 15]))
    }

    func test_isSilentOnlyWhenNothingAtAllIsSelected() {
        // Arrange + Act + Assert
        XCTAssertTrue(ReminderSettings(inheritEventReminders: false, extraMinutes: []).isSilent)
        XCTAssertFalse(ReminderSettings(inheritEventReminders: true, extraMinutes: []).isSilent)
        XCTAssertFalse(ReminderSettings(inheritEventReminders: false, extraMinutes: [1]).isSilent)
    }

    func test_presetLabels() {
        // Arrange + Act + Assert
        XCTAssertEqual(ReminderSettings.label(forMinutes: 0), "At start time")
        XCTAssertEqual(ReminderSettings.label(forMinutes: 1), "1 minute before")
        XCTAssertEqual(ReminderSettings.label(forMinutes: 15), "15 minutes before")
    }

    func test_menuTitleStatesTheSelection() {
        // Arrange
        let both = ReminderSettings(inheritEventReminders: true, extraMinutes: [1, 5])
        let extrasOnly = ReminderSettings(inheritEventReminders: false, extraMinutes: [10])
        let atStart = ReminderSettings(inheritEventReminders: true, extraMinutes: [0, 1])

        // Act + Assert
        XCTAssertEqual(both.menuTitle, "Reminders (calendar + 1, 5 min)")
        XCTAssertEqual(extrasOnly.menuTitle, "Reminders (10 min)")
        XCTAssertEqual(atStart.menuTitle, "Reminders (calendar + 1 min, at start)")
        XCTAssertEqual(ReminderSettings.default.menuTitle, "Reminders (calendar)")
        XCTAssertEqual(ReminderSettings(inheritEventReminders: false, extraMinutes: []).menuTitle, "Reminders (none)")
    }
}
