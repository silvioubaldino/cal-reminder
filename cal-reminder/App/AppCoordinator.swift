import AppKit
import Foundation

/// Wires Auth + Calendar + Scheduler + Overlay together and owns `AppState` (RF-04/RF-06).
/// The MenuBar UI drives this via its public actions and observes `onStateChange`.
@MainActor
final class AppCoordinator {
    private let auth: AuthManaging
    private let calendar: CalendarServicing
    private let scheduler: Scheduling
    private let overlay: OverlayPresenter
    private let pollLoop: PollLoop

    private(set) var state = AppState()
    var onStateChange: ((AppState) -> Void)?

    init(
        auth: AuthManaging,
        calendar: CalendarServicing,
        scheduler: Scheduling,
        overlay: OverlayPresenter,
        pollInterval: TimeInterval = 300
    ) {
        self.auth = auth
        self.calendar = calendar
        self.scheduler = scheduler
        self.overlay = overlay
        self.pollLoop = PollLoop(interval: pollInterval)
        pollLoop.onPoll = { [weak self] in await self?.poll() }
    }

    func start() {
        state.connectionStatus = auth.isConnected ? .connecting : .disconnected
        notify()
        Task {
            await verifySession()
            notify()
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

    func reconnect() {
        Task {
            try? await auth.connect()
            await verifySession()
            notify()
            await poll()
        }
    }

    /// Disconnects the Google account (RF-06 "Sign out of Google"): cancels every armed
    /// Trigger, clears the stored token, and resets to `.disconnected`.
    func logout() {
        Task {
            await scheduler.cancelAll()
            await auth.disconnect()
            state.connectionStatus = .disconnected
            state.nextTrigger = nil
            notify()
        }
    }

    /// Manual Poll (RF-12) from the empty-state menu row: sets `refreshing` for the duration.
    func refreshNow() {
        guard !state.refreshing else { return }
        state.refreshing = true
        notify()
        Task { await poll() }
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
    func poll() async {
        do {
            let triggers = try await calendar.poll()
            await scheduler.schedule(triggers)
            state.connectionStatus = .connected(email: currentEmail)
            // Not `triggers.min(...)`: incremental Polls (RNF-06) only report Events that
            // changed since the last sync, so a still-upcoming, unchanged Trigger can be
            // absent from this Poll's list — the Scheduler holds the accumulated truth.
            state.nextTrigger = await scheduler.nextArmedTrigger()
            state.calendars = (try? await calendar.availableCalendars()) ?? state.calendars
            await refreshUserEmailIfNeeded()
        } catch AuthError.refreshTokenRevoked {
            print("[AppCoordinator] poll failed: refresh token revoked — needs reauth")
            state.connectionStatus = .needsReauth
        } catch {
            print("[AppCoordinator] poll failed: \(error)")
            // Network/transient failure: leave the current status untouched (RNF-04) — only
            // an auth-fatal error (above) drops the session.
        }
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

    private var currentEmail: String? {
        if case .connected(let email) = state.connectionStatus { return email }
        return nil
    }

    /// Verifies the stored session with a real authenticated call (startup / reconnect):
    /// resolves to `.connected(email)` or `.needsReauth`. A network error at verification
    /// time leaves the status as-is (`.connecting`/previous), since a flaky connection at
    /// launch isn't proof the session is dead — the next Poll will resolve it either way.
    private func verifySession() async {
        guard auth.isConnected else {
            state.connectionStatus = .disconnected
            return
        }
        do {
            let email = try await auth.userEmail()
            state.connectionStatus = .connected(email: email)
        } catch AuthError.refreshTokenRevoked {
            state.connectionStatus = .needsReauth
        } catch {
            print("[AppCoordinator] session verification failed: \(error)")
        }
    }

    /// Fetches the connected account's email into state once (RF-06) — skipped once cached.
    private func refreshUserEmailIfNeeded() async {
        guard case .connected(let email) = state.connectionStatus, email == nil else { return }
        if let email = try? await auth.userEmail() {
            state.connectionStatus = .connected(email: email)
        }
    }

    private func notify() {
        onStateChange?(state)
    }
}
