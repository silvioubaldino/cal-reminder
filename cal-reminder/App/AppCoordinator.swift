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
            await scheduler.cancelAll()
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
            minutesBefore: 5
        )
        Task { await overlay.enqueue(trigger) }
    }

    func poll(fullResync: Bool = false) async {
        let result = await accounts.poll(fullResync: fullResync)
        if fullResync && result.anyAccountSucceeded {
            await scheduler.cancelAll()
        }
        await scheduler.schedule(result.triggers)
        syncAccountsState()
        state.nextTrigger = await scheduler.nextArmedTrigger()
        state.refreshing = false
        notify()
    }

    func handleWake() async {
        await scheduler.cancelAll()
        await poll()
    }

    /// The Calendar selection changed (RF-10): drop the armed Triggers and rebuild them from a
    /// **full resync** — same reason as `remindersChanged()`. The Calendars that stayed selected
    /// still hold a `syncToken`, so an incremental Poll would report no Events for them and
    /// leave their upcoming Triggers cancelled and never re-armed.
    func calendarsChanged() {
        Task {
            await scheduler.cancelAll()
            await poll(fullResync: true)
        }
    }

    /// The Reminder selection changed (RF-15): drop the armed Triggers and rebuild them from a
    /// **full resync**. An incremental Poll would return only changed Events (RNF-06), leaving
    /// the upcoming Triggers cancelled and never re-armed.
    func remindersChanged() {
        Task {
            await scheduler.cancelAll()
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
