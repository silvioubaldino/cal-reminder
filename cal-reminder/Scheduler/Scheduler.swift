import Foundation

/// Arms a precise local timer per Trigger and fires `onFire` at `fireDate`, deduping by
/// id (RN-03) and gating firing while paused (AYD-001 Scheduler contract).
protocol Scheduling: AnyObject {
    func reconcile(_ triggers: [Trigger], authoritativeFor accountIds: Set<String>) async
    func setEnabled(_ enabled: Bool) async
    func cancel(accountId: String) async
    func rearmAll() async

    /// The not-yet-fired armed Trigger with the soonest `fireDate`, or `nil` if none is
    /// armed.
    func nextArmedTrigger() async -> Trigger?
}

actor Scheduler: Scheduling {
    private struct Armed {
        let task: Task<Void, Never>
        let trigger: Trigger
        var fireDate: Date { trigger.fireDate }
    }

    private let clock: () -> Date
    private let onFire: (Trigger) -> Void

    private var armed: [String: Armed] = [:]
    private var firedIds: Set<String> = []
    private var enabled = true

    init(clock: @escaping () -> Date = Date.init, onFire: @escaping (Trigger) -> Void) {
        self.clock = clock
        self.onFire = onFire
    }

    func reconcile(_ triggers: [Trigger], authoritativeFor accountIds: Set<String>) {
        for trigger in triggers {
            guard !firedIds.contains(trigger.id) else { continue }
            guard trigger.fireDate > clock() else { continue }
            if let existing = armed[trigger.id], existing.fireDate == trigger.fireDate { continue }
            armed[trigger.id]?.task.cancel()
            arm(trigger)
        }

        let incomingIds = Set(triggers.map(\.id))
        let vanishedIds = armed.values
            .filter { accountIds.contains($0.trigger.accountId) && !incomingIds.contains($0.trigger.id) }
            .map(\.trigger.id)
        for id in vanishedIds {
            armed[id]?.task.cancel()
            armed.removeValue(forKey: id)
        }
    }

    /// Gates firing (RF-06 Pause/Resume): while disabled, armed timers still elapse but skip
    /// `onFire` and don't mark the id as fired.
    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
    }

    func cancel(accountId: String) {
        let ids = armed.values.filter { $0.trigger.accountId == accountId }.map(\.trigger.id)
        for id in ids {
            armed[id]?.task.cancel()
            armed.removeValue(forKey: id)
        }
    }

    func rearmAll() {
        let triggers = armed.values.map(\.trigger)
        for entry in armed.values {
            entry.task.cancel()
        }
        armed.removeAll()

        for trigger in triggers {
            guard !firedIds.contains(trigger.id) else { continue }
            guard trigger.fireDate > clock() else { continue }
            arm(trigger)
        }
    }

    func nextArmedTrigger() -> Trigger? {
        armed.values.min { $0.fireDate < $1.fireDate }?.trigger
    }

    /// Test-only hook (mirrors `OverlayPresenter.waitUntilIdle()`): awaits every currently
    /// armed timer so tests can use short real delays instead of arbitrary sleeps.
    func waitForPendingFires() async {
        for entry in armed.values {
            await entry.task.value
        }
    }

    private func arm(_ trigger: Trigger) {
        let delay = trigger.fireDate.timeIntervalSince(clock())
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(delay, 0) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.fire(trigger)
        }
        armed[trigger.id] = Armed(task: task, trigger: trigger)
    }

    private func fire(_ trigger: Trigger) {
        armed.removeValue(forKey: trigger.id)
        guard enabled else { return }
        firedIds.insert(trigger.id)
        onFire(trigger)
    }
}
