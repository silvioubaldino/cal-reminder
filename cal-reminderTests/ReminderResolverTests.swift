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
}
