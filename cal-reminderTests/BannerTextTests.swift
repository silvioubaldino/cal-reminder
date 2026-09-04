import XCTest
@testable import cal_reminder

final class BannerTextTests: XCTestCase {
    private func date(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 11
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    func test_formatsTitleTimeAndMinutesBefore() {
        // Arrange
        let start = date(hour: 14, minute: 0)

        // Act
        let text = BannerText.bannerText(title: "Standup", start: start, minutesBefore: 5)

        // Assert
        XCTAssertEqual(text, "Standup\nat 14:00 (in 5 min)")
    }

    func test_padsSingleDigitHourAndMinute() {
        // Arrange
        let start = date(hour: 9, minute: 5)

        // Act
        let text = BannerText.bannerText(title: "1:1", start: start, minutesBefore: 10)

        // Assert
        XCTAssertEqual(text, "1:1\nat 09:05 (in 10 min)")
    }

    func test_zeroMinutesBefore_readsStartingNow() {
        // Arrange — an "At start time" Extra Reminder (RF-15)
        let start = date(hour: 8, minute: 30)

        // Act
        let text = BannerText.bannerText(title: "Kickoff", start: start, minutesBefore: 0)

        // Assert
        XCTAssertEqual(text, "Kickoff\nat 08:30 (starting now)")
    }
}
