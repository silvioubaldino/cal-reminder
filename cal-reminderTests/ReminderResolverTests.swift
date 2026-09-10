import XCTest
@testable import cal_reminder

final class ReminderResolverTests: XCTestCase {
    private func event(
        useDefault: Bool,
        overrides: [GoogleEvent.ReminderOverride]? = nil
    ) -> GoogleEvent {
        GoogleEvent(
            id: "evt1",
            summary: "Standup",
            start: .init(dateTime: "2026-07-11T14:00:00-03:00", date: nil),
            status: "confirmed",
            reminders: .init(useDefault: useDefault, overrides: overrides)
        )
    }

    func test_useDefaultTrue_usesCalendarDefaultsAndKeepsOnlyPopup() {
        // Arrange
        let event = event(useDefault: true)
        let defaults = [
            GoogleCalendarDefaultReminder(method: "popup", minutes: 10),
            GoogleCalendarDefaultReminder(method: "email", minutes: 30)
        ]

        // Act
        let minutes = ReminderResolver.popupReminderMinutes(for: event, calendarDefaults: defaults)

        // Assert
        XCTAssertEqual(minutes, [10])
    }

    func test_useDefaultFalse_usesOverridesAndKeepsOnlyPopup() {
        // Arrange
        let event = event(
            useDefault: false,
            overrides: [
                .init(method: "popup", minutes: 5),
                .init(method: "email", minutes: 60)
            ]
        )

        // Act
        let minutes = ReminderResolver.popupReminderMinutes(for: event, calendarDefaults: [
            GoogleCalendarDefaultReminder(method: "popup", minutes: 10)
        ])

        // Assert
        XCTAssertEqual(minutes, [5])
    }

    func test_missingRemindersField_defaultsToUseDefaultTrue() {
        // Arrange
        let event = GoogleEvent(
            id: "evt1",
            summary: "Standup",
            start: .init(dateTime: "2026-07-11T14:00:00-03:00", date: nil),
            status: "confirmed",
            reminders: nil
        )
        let defaults = [GoogleCalendarDefaultReminder(method: "popup", minutes: 10)]

        // Act
        let minutes = ReminderResolver.popupReminderMinutes(for: event, calendarDefaults: defaults)

        // Assert
        XCTAssertEqual(minutes, [10])
    }

    func test_multiplePopupOverrides_areAllKept() {
        // Arrange
        let event = event(
            useDefault: false,
            overrides: [
                .init(method: "popup", minutes: 10),
                .init(method: "popup", minutes: 2)
            ]
        )

        // Act
        let minutes = ReminderResolver.popupReminderMinutes(for: event, calendarDefaults: [])

        // Assert
        XCTAssertEqual(minutes, [10, 2])
    }

    func test_useDefaultTrue_noPopupCalendarDefault_fallsBackToFiveMinutes() {
        // Arrange
        let event = event(useDefault: true)
        let defaults = [GoogleCalendarDefaultReminder(method: "email", minutes: 30)]

        // Act
        let minutes = ReminderResolver.popupReminderMinutes(for: event, calendarDefaults: defaults)

        // Assert
        XCTAssertEqual(minutes, [5])
    }

    func test_useDefaultFalse_noPopupOverride_fallsBackToFiveMinutes() {
        // Arrange
        let event = event(
            useDefault: false,
            overrides: [.init(method: "email", minutes: 60)]
        )

        // Act
        let minutes = ReminderResolver.popupReminderMinutes(for: event, calendarDefaults: [
            GoogleCalendarDefaultReminder(method: "popup", minutes: 10)
        ])

        // Assert
        XCTAssertEqual(minutes, [5])
    }

    func test_useDefaultFalse_emptyOverrides_fallsBackToFiveMinutes() {
        // Arrange
        let event = event(useDefault: false, overrides: [])

        // Act
        let minutes = ReminderResolver.popupReminderMinutes(for: event, calendarDefaults: [])

        // Assert
        XCTAssertEqual(minutes, [5])
    }

    // MARK: - RN-07: union with the Extra Reminders (RF-15)

    func test_defaultSettings_behaveExactlyLikeBeforeExtraReminders() {
        // Arrange
        let event = event(useDefault: false, overrides: [.init(method: "popup", minutes: 10)])

        // Act
        let minutes = ReminderResolver.popupReminderMinutes(
            for: event,
            calendarDefaults: [],
            settings: .default
        )

        // Assert
        XCTAssertEqual(minutes, [10])
    }

    func test_extraReminder_isAddedOnTopOfTheEventsOwn() {
        // Arrange
        let event = event(useDefault: false, overrides: [.init(method: "popup", minutes: 10)])

        // Act
        let minutes = ReminderResolver.popupReminderMinutes(
            for: event,
            calendarDefaults: [],
            settings: ReminderSettings(inheritEventReminders: true, extraMinutes: [1])
        )

        // Assert
        XCTAssertEqual(minutes, [10, 1])
    }

    func test_fallbackStillApplies_underAnExtraReminder() {
        // Arrange
        let event = event(useDefault: true)

        // Act
        let minutes = ReminderResolver.popupReminderMinutes(
            for: event,
            calendarDefaults: [],
            settings: ReminderSettings(inheritEventReminders: true, extraMinutes: [1])
        )

        // Assert
        XCTAssertEqual(minutes, [5, 1])
    }

    func test_extraReminderDuplicatingTheEventsOwn_resolvesOnce() {
        // Arrange
        let event = event(useDefault: false, overrides: [.init(method: "popup", minutes: 5)])

        // Act
        let minutes = ReminderResolver.popupReminderMinutes(
            for: event,
            calendarDefaults: [],
            settings: ReminderSettings(inheritEventReminders: true, extraMinutes: [5])
        )

        // Assert
        XCTAssertEqual(minutes, [5])
    }

    func test_inheritOff_resolvesToTheExtraRemindersOnly() {
        // Arrange
        let event = event(useDefault: false, overrides: [.init(method: "popup", minutes: 30)])

        // Act
        let minutes = ReminderResolver.popupReminderMinutes(
            for: event,
            calendarDefaults: [GoogleCalendarDefaultReminder(method: "popup", minutes: 20)],
            settings: ReminderSettings(inheritEventReminders: false, extraMinutes: [1, 15])
        )

        // Assert
        XCTAssertEqual(minutes, [1, 15])
    }

    func test_inheritOff_doesNotApplyTheFiveMinuteFallback() {
        // Arrange
        let event = event(useDefault: true)

        // Act
        let minutes = ReminderResolver.popupReminderMinutes(
            for: event,
            calendarDefaults: [],
            settings: ReminderSettings(inheritEventReminders: false, extraMinutes: [1])
        )

        // Assert
        XCTAssertEqual(minutes, [1])
    }

    func test_nothingSelected_resolvesToNoReminderAtAll() {
        // Arrange
        let event = event(useDefault: false, overrides: [.init(method: "popup", minutes: 10)])

        // Act
        let minutes = ReminderResolver.popupReminderMinutes(
            for: event,
            calendarDefaults: [],
            settings: ReminderSettings(inheritEventReminders: false, extraMinutes: [])
        )

        // Assert
        XCTAssertTrue(minutes.isEmpty)
    }

    func test_extraRemindersAreOrderedAscending_afterTheInheritedOnes() {
        // Arrange
        let event = event(useDefault: false, overrides: [.init(method: "popup", minutes: 10)])

        // Act
        let minutes = ReminderResolver.popupReminderMinutes(
            for: event,
            calendarDefaults: [],
            settings: ReminderSettings(inheritEventReminders: true, extraMinutes: [15, 0, 1])
        )

        // Assert
        XCTAssertEqual(minutes, [10, 0, 1, 15])
    }
}
