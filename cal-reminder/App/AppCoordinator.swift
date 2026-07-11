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
        pollInterval: TimeInterval = 120
    ) {
        self.auth = auth
        self.calendar = calendar
        self.scheduler = scheduler
        self.overlay = overlay
        self.pollLoop = PollLoop(interval: pollInterval)
        pollLoop.onPoll = { [weak self] in await self?.poll() }
    }

    func start() {
        state.connected = auth.isConnected
        notify()
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
            state.connected = auth.isConnected
            notify()
            await poll()
        }
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
            state.connected = true
            state.nextTrigger = triggers.min { $0.fireDate < $1.fireDate }
        } catch {
            state.connected = auth.isConnected
        }
        notify()
    }

    /// Not `private`: see `poll()`.
    func handleWake() async {
        await scheduler.cancelAll()
        await poll()
    }

    private func notify() {
        onStateChange?(state)
    }
}
