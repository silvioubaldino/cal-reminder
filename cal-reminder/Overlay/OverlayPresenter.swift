import AppKit

/// Plays the Airplane + Banner flight for a given Banner text. Abstracted so the FIFO
/// queue in `OverlayPresenter` can be tested without driving real AppKit windows.
protocol OverlayAnimating {
    func animate(text: String) async
}

/// Default animator: shows an `OverlayPanel` over `NSScreen.main`, plays the flight on
/// an `AirplaneBannerView` at the current Flight Speed (RF-07), then hides the panel again.
@MainActor
final class DefaultOverlayAnimator: OverlayAnimating {
    private let speedStore: FlightSpeedStoring

    init(speedStore: FlightSpeedStoring = UserDefaultsFlightSpeedStore()) {
        self.speedStore = speedStore
    }

    func animate(text: String) async {
        guard let screen = NSScreen.main else { return }

        let panel = OverlayPanel(screen: screen)
        let view = AirplaneBannerView(frame: CGRect(origin: .zero, size: screen.frame.size))
        panel.contentView = view

        panel.orderFrontRegardless()
        await view.animate(text: text, duration: speedStore.flightSpeed.flightDuration)
        panel.orderOut(nil)
    }
}

/// Receives Triggers and plays their animation one at a time, in arrival order (RN-05).
actor OverlayPresenter {
    private let animator: OverlayAnimating
    private var queue: [Trigger] = []
    private var drainTask: Task<Void, Never>?

    init(animator: OverlayAnimating) {
        self.animator = animator
    }

    func enqueue(_ trigger: Trigger) {
        queue.append(trigger)
        if drainTask == nil {
            drainTask = Task { await drain() }
        }
    }

    /// Test-only hook: suspends until the queue has fully drained.
    func waitUntilIdle() async {
        await drainTask?.value
    }

    private func drain() async {
        while !queue.isEmpty {
            let trigger = queue.removeFirst()
            let text = BannerText.bannerText(
                title: trigger.eventTitle,
                start: trigger.startDate,
                minutesBefore: trigger.minutesBefore
            )
            await animator.animate(text: text)
        }
        drainTask = nil
    }
}
