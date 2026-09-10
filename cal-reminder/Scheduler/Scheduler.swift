import Foundation

/// Arms a precise local timer per Trigger and fires `onFire` at `fireDate`, deduping by
/// id (RN-03) and gating firing while paused (AYD-001 Scheduler contract).
///
/// The armed set is a **reconciliation** against the Poll's complete desired set (AYD-011),
/// not an accumulation across Polls: `reconcile(_:authoritativeFor:)` arms what's new, re-arms
/// what moved, and cancels what is missing from an Account the Poll actually heard back from —
/// an Account whose Poll failed this round is left untouched, so its armed Triggers survive.
protocol Scheduling: AnyObject {
    /// Reconciles the armed set against `triggers`, the complete desired set derived from a
    /// Poll. Only Triggers belonging to `accountIds` — the Accounts that Poll actually
    /// succeeded for — are eligible to be cancelled when they're absent from `triggers`; an
    /// armed Trigger for an Account outside that scope (its Poll failed, or it wasn't polled
    /// this round) is left alone (RNF-04, RF-14).
    func reconcile(_ triggers: [Trigger], authoritativeFor accountIds: Set<String>) async
    func setEnabled(_ enabled: Bool) async
    /// Cancels every armed Trigger for one Account without touching any other Account's
    /// (RF-14) — used when that Account is signed out.
    func cancel(accountId: String) async
    /// Re-arms every still-armed, not-yet-fired Trigger against the current clock, without
    /// dropping any of them — used on wake from sleep (RNF-04), since `Task.sleep`'s clock
    /// doesn't advance while the Mac is asleep.
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
