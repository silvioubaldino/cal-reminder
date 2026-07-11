import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenuController: StatusMenuController?
    private let flightSpeedStore = UserDefaultsFlightSpeedStore()
    private lazy var overlayPresenter = OverlayPresenter(
        animator: DefaultOverlayAnimator(speedStore: flightSpeedStore)
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusMenuController = StatusMenuController(
            onTestAnimation: { [weak self] in
                self?.runTestAnimation()
            },
            speedStore: flightSpeedStore
        )
    }

    private func runTestAnimation() {
        let now = Date()
        let trigger = Trigger(
            id: "test#5",
            eventTitle: "Standup",
            startDate: now.addingTimeInterval(5 * 60),
            fireDate: now,
            minutesBefore: 5
        )
        Task { await overlayPresenter.enqueue(trigger) }
    }
}
