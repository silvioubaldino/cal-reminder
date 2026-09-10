import AppKit
import Foundation

@MainActor
final class AppCoordinator {
    private let accounts: AccountsManaging
    private let scheduler: Scheduling
    private let overlay: OverlayPresenter
    private let pollLoop: PollLoop
    private var didRestore = false

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
        pollLoop.onPoll = { [weak self] in
            guard let self else { return }
            if !self.didRestore {
                self.didRestore = true
                await self.accounts.restore()
                self.syncAccountsState()
                self.notify()
                await self.accounts.verifySessions()
                self.syncAccountsState()
                self.notify()
            }
            await self.poll()
        }
    }

    func start() {
        pollLoop.start()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in await self?.handleWake() }
        }
    }

    func setOAuthConfigured(_ configured: Bool) {
        state.oauthConfigured = configured
        notify()
    }

    func setUpdateStatus(_ status: UpdateStatus) {
        state.updateStatus = status
        notify()
    }

    func toggleEnabled() {
        state.enabled.toggle()
        let enabled = state.enabled
        Task { await scheduler.setEnabled(enabled) }
        notify()
    }

    func addAccount() {
        Task {
            _ = try? await accounts.addAccount(provider: .google)
            await poll()
        }
    }

    func reconnect(accountId: String) {
        Task {
            try? await accounts.reconnect(accountId: accountId)
            await poll()
        }
    }

    func signOut(accountId: String) {
        Task {
            await accounts.signOut(accountId: accountId)
            await scheduler.cancel(accountId: accountId)
            await poll()
        }
    }

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
            minutesBefore: 5,
            accountId: "test"
        )
        Task { await overlay.enqueue(trigger) }
    }

    /// A Poll's result is already the complete desired set for every Account it succeeded for
    /// (AYD-011) — the Scheduler reconciles against it directly instead of being cancelled and
    /// rebuilt, so an Account whose Poll failed this round keeps its previously armed Triggers.
    func poll(fullResync: Bool = false) async {
        let result = await accounts.poll(fullResync: fullResync)
        await scheduler.reconcile(result.triggers, authoritativeFor: result.authoritativeAccountIds)
        syncAccountsState()
        state.nextTrigger = await scheduler.nextArmedTrigger()
        state.refreshing = false
        notify()
    }

    /// `Task.sleep`'s clock doesn't advance while the Mac is asleep, so an armed Trigger would
    /// otherwise fire late (RNF-04): re-arm every one of them against the current clock first,
    /// then re-sync — an incremental Poll here would report no changed Events and, under the
    /// old cancel-then-poll flow, silently drop everything still pending.
    func handleWake() async {
        await scheduler.rearmAll()
        await poll()
    }

    /// The Calendar selection changed (RF-10): rebuild the Triggers from a **full resync** —
    /// same reason as `remindersChanged()`. `poll(fullResync:)`'s reconcile already drops a
    /// deselected Calendar's Triggers, since they're simply absent from the fresh result.
    func calendarsChanged() {
        Task {
            await poll(fullResync: true)
        }
    }

    /// The Reminder selection changed (RF-15): rebuild the Triggers from a **full resync**. An
    /// incremental Poll would return only changed Events (RNF-06), which the reconcile would
    /// wrongly read as "everything else is gone".
    func remindersChanged() {
        Task {
            await poll(fullResync: true)
        }
    }

    private func syncAccountsState() {
        state.accounts = accounts.sessions.map {
            AccountState(id: $0.id, label: $0.account.label, connectionStatus: $0.connectionStatus, calendars: $0.calendars)
        }
    }

    private func notify() {
        onStateChange?(state)
    }
}
