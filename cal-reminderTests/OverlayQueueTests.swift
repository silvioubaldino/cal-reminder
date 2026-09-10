import XCTest
@testable import cal_reminder

/// Stub animator that records call order and detects overlap by tracking how many
/// animations are in flight at once.
private actor SpyAnimator: OverlayAnimating {
    private(set) var playedTexts: [String] = []
    /// The Calendar Color each flight was asked to paint with (RF-13), in play order.
    private(set) var playedColorHexes: [String?] = []
    private(set) var maxConcurrent = 0
    private var inFlight = 0

    func animate(text: String, calendarColorHex: String?) async {
        inFlight += 1
        maxConcurrent = max(maxConcurrent, inFlight)
        playedTexts.append(text)
        playedColorHexes.append(calendarColorHex)
        try? await Task.sleep(nanoseconds: 20_000_000)
        inFlight -= 1
    }
}

final class OverlayQueueTests: XCTestCase {
    private func trigger(id: String, title: String, calendarColorHex: String? = nil) -> Trigger {
        Trigger(
            id: id,
            eventTitle: title,
            startDate: Date(),
            fireDate: Date(),
            minutesBefore: 5,
            calendarColorHex: calendarColorHex,
            accountId: "acct1"
        )
    }

    func test_playsAnimationsInArrivalOrderWithoutOverlap() async {
        // Arrange
        let spy = SpyAnimator()
        let presenter = OverlayPresenter(animator: spy)

        // Act
        await presenter.enqueue(trigger(id: "1#5", title: "First"))
        await presenter.enqueue(trigger(id: "2#5", title: "Second"))
        await presenter.enqueue(trigger(id: "3#5", title: "Third"))
        await presenter.waitUntilIdle()

        // Assert
        let played = await spy.playedTexts
        XCTAssertEqual(played.count, 3)
        XCTAssertTrue(played[0].hasPrefix("First"))
        XCTAssertTrue(played[1].hasPrefix("Second"))
        XCTAssertTrue(played[2].hasPrefix("Third"))

        let maxConcurrent = await spy.maxConcurrent
        XCTAssertEqual(maxConcurrent, 1)
    }

    func test_forwardsEachTriggersCalendarColorToTheAnimator() async {
        // Arrange (RF-13: the Banner is painted per Trigger, not per app)
        let spy = SpyAnimator()
        let presenter = OverlayPresenter(animator: spy)

        // Act
        await presenter.enqueue(trigger(id: "1#5", title: "Work", calendarColorHex: "#0b8043"))
        await presenter.enqueue(trigger(id: "2#5", title: "Colorless", calendarColorHex: nil))
        await presenter.waitUntilIdle()

        // Assert
        let colors = await spy.playedColorHexes
        XCTAssertEqual(colors, ["#0b8043", nil])
    }
}
