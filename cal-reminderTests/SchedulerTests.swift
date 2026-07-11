import XCTest
@testable import cal_reminder

/// Records fired Trigger ids, mirroring `OverlayQueueTests`'s `SpyAnimator`.
private actor FireSpy {
    private(set) var firedIds: [String] = []

    func record(_ trigger: Trigger) {
        firedIds.append(trigger.id)
    }
}

final class SchedulerTests: XCTestCase {
    private func trigger(id: String, fireDate: Date) -> Trigger {
        Trigger(id: id, eventTitle: "Standup", startDate: fireDate, fireDate: fireDate, minutesBefore: 5)
    }

    private func makeScheduler(spy: FireSpy) -> Scheduler {
        Scheduler(onFire: { trigger in Task { await spy.record(trigger) } })
    }

    func test_firesCloseToFireDate() async throws {
        // Arrange
        let spy = FireSpy()
        let scheduler = makeScheduler(spy: spy)
        let fireDate = Date().addingTimeInterval(0.05)

        // Act
        await scheduler.schedule([trigger(id: "evt1#5", fireDate: fireDate)])
        await scheduler.waitForPendingFires()
        try await Task.sleep(nanoseconds: 20_000_000)

        // Assert
        let fired = await spy.firedIds
        XCTAssertEqual(fired, ["evt1#5"])
    }

    func test_sameIdNeverFiresTwice() async throws {
        // Arrange
        let spy = FireSpy()
        let scheduler = makeScheduler(spy: spy)
        let sameTrigger = trigger(id: "evt1#10", fireDate: Date().addingTimeInterval(0.02))

        // Act
        await scheduler.schedule([sameTrigger])
        await scheduler.waitForPendingFires()
        try await Task.sleep(nanoseconds: 20_000_000)
        await scheduler.schedule([sameTrigger]) // poll() returns the same Trigger again
        await scheduler.waitForPendingFires()
        try await Task.sleep(nanoseconds: 20_000_000)

        // Assert
        let fired = await spy.firedIds
        XCTAssertEqual(fired, ["evt1#10"])
    }

    func test_noFireWhileDisabled() async throws {
        // Arrange
        let spy = FireSpy()
        let scheduler = makeScheduler(spy: spy)

        // Act
        await scheduler.setEnabled(false)
        await scheduler.schedule([trigger(id: "evt1#5", fireDate: Date().addingTimeInterval(0.02))])
        await scheduler.waitForPendingFires()
        try await Task.sleep(nanoseconds: 20_000_000)

        // Assert
        let fired = await spy.firedIds
        XCTAssertTrue(fired.isEmpty)
    }

    func test_pastDueTriggersAreNeverArmed() async {
        // Arrange
        let spy = FireSpy()
        let scheduler = makeScheduler(spy: spy)
        let pastFireDate = Date().addingTimeInterval(-60)

        // Act
        await scheduler.schedule([trigger(id: "evt1#5", fireDate: pastFireDate)])
        await scheduler.waitForPendingFires()

        // Assert
        let fired = await spy.firedIds
        XCTAssertTrue(fired.isEmpty)
    }
}
