import AppKit

/// Plays the Airplane + Banner flight for a given Banner text. Abstracted so the FIFO
/// queue in `OverlayPresenter` can be tested without driving real AppKit windows.
protocol OverlayAnimating {
    /// `calendarColorHex` is the Calendar Color of the Event's Calendar (RF-13), or nil
    /// when there is none (colorless Calendar, or the test animation) — the animator then
    /// falls back to the Banner color preset (RF-08).
    func animate(text: String, calendarColorHex: String?) async
}

/// Default animator: shows an `OverlayPanel` over `NSScreen.main`, plays the flight on
/// an `AirplaneBannerView` at the current Flight Speed (RF-07), then hides the panel again.
@MainActor
final class DefaultOverlayAnimator: OverlayAnimating {
    private let speedStore: FlightSpeedStoring
    private let colorStore: BannerColorStoring
    private let matchCalendarColorStore: MatchCalendarColorStoring
    private let skipOnClickStore: SkipOnClickStoring

    init(
        speedStore: FlightSpeedStoring = UserDefaultsFlightSpeedStore(),
        colorStore: BannerColorStoring = UserDefaultsBannerColorStore(),
        matchCalendarColorStore: MatchCalendarColorStoring = UserDefaultsMatchCalendarColorStore(),
        skipOnClickStore: SkipOnClickStoring = UserDefaultsSkipOnClickStore()
    ) {
        self.speedStore = speedStore
        self.colorStore = colorStore
        self.matchCalendarColorStore = matchCalendarColorStore
        self.skipOnClickStore = skipOnClickStore
    }

    /// The Banner's background for this flight: the Event's Calendar Color when the user
    /// asked for it and it parses, otherwise the chosen preset (RF-13 falls back to RF-08).
    func bannerBackgroundColor(for calendarColorHex: String?) -> NSColor {
        guard matchCalendarColorStore.matchCalendarColor,
              let calendarColorHex,
              let color = NSColor(bannerHex: calendarColorHex) else {
            return colorStore.bannerColor.color
        }
        return color
    }

    func animate(text: String, calendarColorHex: String?) async {
        guard let screen = NSScreen.main else { return }

        let skipOnClick = skipOnClickStore.skipOnClick

        let panel = OverlayPanel(screen: screen)
        let view = AirplaneBannerView(frame: CGRect(origin: .zero, size: screen.frame.size))
        // Both colors are converted to the color space of the screen they'll be painted on,
        // so a Calendar Color renders as the same tone the user sees in Google Calendar
        // rather than as raw sRGB components on a wide-gamut display (TDR-004).
        let background = bannerBackgroundColor(for: calendarColorHex)
        let textColor = background.readableBannerTextColor
        view.setBannerColor(background.matchingDisplayColorSpace(screen.colorSpace))
        view.setBannerTextColor(textColor.matchingDisplayColorSpace(screen.colorSpace))
        if skipOnClick {
            view.onSkipRequested = { [weak view] in view?.skipToEnd() }
        }
        panel.contentView = view

        panel.orderFrontRegardless()
        // Click-through by default (RNF-02); accept clicks only while this flight plays
        // and only when the user opted into click-to-skip (RF-09) — otherwise the panel
        // stays click-through for the whole flight and the Airplane finishes on its own.
        panel.ignoresMouseEvents = !skipOnClick
        await view.animate(text: text, speed: speedStore.flightSpeed)
        panel.ignoresMouseEvents = true
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
            await animator.animate(text: text, calendarColorHex: trigger.calendarColorHex)
        }
        drainTask = nil
    }
}
