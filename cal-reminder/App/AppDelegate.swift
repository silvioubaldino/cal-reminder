import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenuController: StatusMenuController?
    private let overlayPresenter = OverlayPresenter(animator: DefaultOverlayAnimator())

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusMenuController = StatusMenuController(onTestAnimation: { [weak self] in
            self?.runTestAnimation()
        })
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
