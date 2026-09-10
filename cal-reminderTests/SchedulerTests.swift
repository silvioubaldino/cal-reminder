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
    private func trigger(id: String, fireDate: Date, accountId: String = "acct1") -> Trigger {
        Trigger(id: id, eventTitle: "Standup", startDate: fireDate, fireDate: fireDate, minutesBefore: 5, accountId: accountId)
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
        await scheduler.reconcile([trigger(id: "evt1#5", fireDate: fireDate)], authoritativeFor: ["acct1"])
        await scheduler.waitForPendingFires()
        try await Task.sleep(nanoseconds: 20_000_000)

        // Assert
        let fired = await spy.firedIds
        XCTAssertEqual(fired, ["evt1#5"])
    }

    func test_reconcileNeverReplaysAnAlreadyFiredReminder() async throws {
        // Arrange
        let spy = FireSpy()
        let scheduler = makeScheduler(spy: spy)
        let sameTrigger = trigger(id: "evt1#10", fireDate: Date().addingTimeInterval(0.02))

        // Act
        await scheduler.reconcile([sameTrigger], authoritativeFor: ["acct1"])
        await scheduler.waitForPendingFires()
        try await Task.sleep(nanoseconds: 20_000_000)
        await scheduler.reconcile([sameTrigger], authoritativeFor: ["acct1"]) // Poll returns the same Trigger again
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
        await scheduler.reconcile([trigger(id: "evt1#5", fireDate: Date().addingTimeInterval(0.02))], authoritativeFor: ["acct1"])
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
        await scheduler.reconcile([trigger(id: "evt1#5", fireDate: pastFireDate)], authoritativeFor: ["acct1"])
        await scheduler.waitForPendingFires()

        // Assert
        let fired = await spy.firedIds
        XCTAssertTrue(fired.isEmpty)
    }

    func test_nextArmedTriggerReflectsSoonestAcrossSeparateAccountsReconciles() async {
        // Arrange
        let spy = FireSpy()
        let scheduler = makeScheduler(spy: spy)
        let later = trigger(id: "acctA#evt2#5", fireDate: Date().addingTimeInterval(120), accountId: "acctA")
        let soon = trigger(id: "acctB#evt1#5", fireDate: Date().addingTimeInterval(60), accountId: "acctB")

        // Act
        await scheduler.reconcile([later], authoritativeFor: ["acctA"])
        await scheduler.reconcile([soon], authoritativeFor: ["acctB"])

        // Assert
        let next = await scheduler.nextArmedTrigger()
        XCTAssertEqual(next?.id, "acctB#evt1#5")
    }

    func test_reconcileCancelsATriggerAbsentFromTheNewAuthoritativeSet() async {
        // Arrange
        let spy = FireSpy()
        let scheduler = makeScheduler(spy: spy)
        await scheduler.reconcile([trigger(id: "evt1#5", fireDate: Date().addingTimeInterval(60))], authoritativeFor: ["acct1"])

        // Act
        await scheduler.reconcile([], authoritativeFor: ["acct1"])

        // Assert
        let next = await scheduler.nextArmedTrigger()
        XCTAssertNil(next)
    }

    func test_reconcileDoesNotCancelTriggersOutsideItsAuthoritativeScope() async {
        // Arrange
        let spy = FireSpy()
        let scheduler = makeScheduler(spy: spy)
        let accountBTrigger = trigger(id: "acctB#evt1#5", fireDate: Date().addingTimeInterval(30), accountId: "acctB")
        await scheduler.reconcile([accountBTrigger], authoritativeFor: ["acctB"])

        // Act
        let accountATrigger = trigger(id: "acctA#evt2#5", fireDate: Date().addingTimeInterval(60), accountId: "acctA")
        await scheduler.reconcile([accountATrigger], authoritativeFor: ["acctA"])

        // Assert
        let next = await scheduler.nextArmedTrigger()
        XCTAssertEqual(next?.id, "acctB#evt1#5")
    }

    func test_cancelAccountDropsOnlyThatAccountsTriggers() async {
        // Arrange
        let spy = FireSpy()
        let scheduler = makeScheduler(spy: spy)
        await scheduler.reconcile(
            [
                trigger(id: "acctA#evt1#5", fireDate: Date().addingTimeInterval(60), accountId: "acctA"),
                trigger(id: "acctB#evt1#5", fireDate: Date().addingTimeInterval(30), accountId: "acctB")
            ],
            authoritativeFor: ["acctA", "acctB"]
        )

        // Act
        await scheduler.cancel(accountId: "acctB")

        // Assert
        let next = await scheduler.nextArmedTrigger()
        XCTAssertEqual(next?.id, "acctA#evt1#5")
    }

    func test_rearmAllKeepsArmedTriggersAndRecomputesTheirDelay() async throws {
        // Arrange
        let spy = FireSpy()
        let scheduler = makeScheduler(spy: spy)
        let fireDate = Date().addingTimeInterval(120)
        await scheduler.reconcile([trigger(id: "evt1#5", fireDate: fireDate)], authoritativeFor: ["acct1"])

        // Act
        await scheduler.rearmAll()

        // Assert
        let next = await scheduler.nextArmedTrigger()
        XCTAssertEqual(next?.id, "evt1#5")
        XCTAssertEqual(next?.fireDate, fireDate)
    }

    func test_rearmAllDropsATriggerThatWentPastDueWhileAsleep() async throws {
        // Arrange
        let spy = FireSpy()
        let clock = MutableClock(now: Date())
        let scheduler = Scheduler(clock: clock.now, onFire: { trigger in Task { await spy.record(trigger) } })
        let soonToBePastDue = trigger(id: "evt1#5", fireDate: clock.currentDate.addingTimeInterval(60))
        let stillUpcoming = trigger(id: "evt2#5", fireDate: clock.currentDate.addingTimeInterval(600))
        await scheduler.reconcile([soonToBePastDue, stillUpcoming], authoritativeFor: ["acct1"])

        // Act
        clock.advance(by: 120)
        await scheduler.rearmAll()

        // Assert
        let next = await scheduler.nextArmedTrigger()
        XCTAssertEqual(next?.id, "evt2#5")
    }
}

private final class MutableClock {
    private var date: Date
    init(now: Date) { self.date = now }
    var currentDate: Date { date }
    func now() -> Date { date }
    func advance(by seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}
