import AppKit
import Foundation

/// Wires Accounts + Scheduler + Overlay together and owns `AppState` (RF-04/RF-06/RF-14).
/// The MenuBar UI drives this via its public actions and observes `onStateChange`.
@MainActor
final class AppCoordinator {
    private let accounts: AccountsManaging
    private let scheduler: Scheduling
    private let overlay: OverlayPresenter
    private let pollLoop: PollLoop

    private(set) var state = AppState()
    var onStateChange: ((AppState) -> Void)?

    init(
        accounts: AccountsManaging,
        scheduler: Scheduling,
        overlay: OverlayPresenter,
        pollInterval: TimeInterval = 300
    ) {
        self.accounts = accounts
        self.scheduler = scheduler
        self.overlay = overlay
        self.pollLoop = PollLoop(interval: pollInterval)
        pollLoop.onPoll = { [weak self] in await self?.poll() }
    }

    func start() {
        Task {
            await accounts.restore()
            syncAccountsState()
            notify()
            await accounts.verifySessions()
            syncAccountsState()
            notify()
            await poll()
        }
        pollLoop.start()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in await self?.handleWake() }
        }
    }

    func toggleEnabled() {
        state.enabled.toggle()
        let enabled = state.enabled
        Task { await scheduler.setEnabled(enabled) }
        notify()
    }

    /// Starts the OAuth flow for a brand-new Google Account (RF-14), then re-Polls so its
    /// Triggers show up immediately (mirrors `calendarsChanged()`).
    func addAccount() {
        Task {
            _ = try? await accounts.addAccount(provider: .google)
            await poll()
        }
    }

    /// Re-authorizes a specific Account (RF-14), pre-selecting it in Google's chooser.
    func reconnect(accountId: String) {
        Task {
            try? await accounts.reconnect(accountId: accountId)
            await poll()
        }
    }

    /// Disconnects one Google Account (RF-14 "Sign out"): cancels every armed Trigger and
    /// re-Polls from the remaining Accounts, so the signed-out one's Triggers disappear
    /// without disturbing the others.
    func signOut(accountId: String) {
        Task {
            await accounts.signOut(accountId: accountId)
            await scheduler.cancelAll()
            await poll()
        }
    }

    /// Manual Poll (RF-12) from the "Refresh now" menu item: sets `refreshing` for the
    /// duration and runs a **full resync** (SPEC-013), so a stale state is rebuilt rather
    /// than merged into — an incremental delta can't drop a Trigger whose Event is gone.
    func refreshNow() {
        guard !state.refreshing else { return }
        state.refreshing = true
        notify()
        Task { await poll(fullResync: true) }
    }

    func testAnimation() {
        let now = Date()
        let trigger = Trigger(
            id: "test#5",
            eventTitle: "Standup",
            startDate: now.addingTimeInterval(5 * 60),
            fireDate: now,
            minutesBefore: 5
        )
        Task { await overlay.enqueue(trigger) }
    }

    /// Not `private`: exercised directly by `AppCoordinatorTests` (via `@testable import`)
    /// to assert `AppState` transitions deterministically, without going through the
    /// fire-and-forget `PollLoop`/`Task` wrappers real callers use.
    func poll(fullResync: Bool = false) async {
        let result = await accounts.poll(fullResync: fullResync)
        // A full resync (SPEC-013) returns the complete window per Account, so it *replaces*
        // the accumulated armed set instead of merging into it — that's what drops Triggers
        // whose Event was deleted or moved out of the window. Gated on `anyAccountSucceeded`:
        // a total outage across every Account must not wipe the armed set on a failed manual
        // refresh (RNF-04) — mirrors the single-account build never reaching `cancelAll()`
        // when its one-and-only Poll call threw.
        if fullResync && result.anyAccountSucceeded {
            await scheduler.cancelAll()
        }
        await scheduler.schedule(result.triggers)
        syncAccountsState()
        // Not `triggers.min(...)`: incremental Polls (RNF-06) only report Events that
        // changed since the last sync, so a still-upcoming, unchanged Trigger can be
        // absent from this Poll's list — the Scheduler holds the accumulated truth.
        state.nextTrigger = await scheduler.nextArmedTrigger()
        state.refreshing = false
        notify()
    }

    /// Not `private`: see `poll()`.
    func handleWake() async {
        await scheduler.cancelAll()
        await poll()
    }

    /// A Calendar-selection change (RF-10): re-arm from a fresh Poll immediately, mirroring
    /// `handleWake()`, instead of waiting for the PollLoop.
    func calendarsChanged() {
        Task {
            await scheduler.cancelAll()
            await poll()
        }
    }

    /// Rebuilds `state.accounts` from the registry's current sessions.
    private func syncAccountsState() {
        state.accounts = accounts.sessions.map {
            AccountState(id: $0.id, label: $0.account.label, connectionStatus: $0.connectionStatus, calendars: $0.calendars)
        }
    }

    private func notify() {
        onStateChange?(state)
    }
}
