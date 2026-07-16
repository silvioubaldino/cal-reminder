import Cocoa

/// A checkbox row for the "Calendars" submenu (RF-10). Uses a custom `NSMenuItem.view`
/// instead of a plain item + action: `NSMenu` only auto-dismisses when a *menu item*
/// sends its action, and a custom view's button click is handled entirely within the
/// button's own tracking loop — so the menu stays open across multiple toggles.
private final class CalendarCheckboxView: NSView {
    private let checkbox: NSButton
    private let onToggle: (Bool) -> Void

    init(title: String, isChecked: Bool, onToggle: @escaping (Bool) -> Void) {
        self.onToggle = onToggle
        checkbox = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        checkbox.state = isChecked ? .on : .off
        checkbox.sizeToFit()

        // Frame-based, not Auto Layout: NSMenu reads `view.frame.size` directly to size
        // the row — it never triggers a constraint-based layout pass for custom item views.
        let horizontalPadding: CGFloat = 18
        let verticalPadding: CGFloat = 2
        let size = NSSize(
            width: checkbox.frame.width + horizontalPadding + 14,
            height: checkbox.frame.height + verticalPadding * 2
        )
        super.init(frame: NSRect(origin: .zero, size: size))

        checkbox.frame.origin = NSPoint(x: horizontalPadding, y: verticalPadding)
        addSubview(checkbox)
        checkbox.target = self
        checkbox.action = #selector(handleToggle)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleToggle() {
        onToggle(checkbox.state == .on)
    }
}

/// The `NSStatusItem` menu (RF-06): connection status, next upcoming Trigger, Pause/Resume,
/// test animation, Flight Speed, Reconnect Google, and Quit. `render(_:)` reflects the
/// `AppCoordinator`'s `AppState` after every change.
final class StatusMenuController {
    private let statusItem: NSStatusItem
    private let onTestAnimation: () -> Void
    private let onToggleEnabled: () -> Void
    private let onReconnect: () -> Void
    private let onSignOut: () -> Void
    private let onRefresh: () -> Void
    private let onCalendarsChanged: () -> Void
    private let speedStore: FlightSpeedStoring
    private let colorStore: BannerColorStoring
    private let calendarSelectionStore: CalendarSelectionStoring
    private var speedItems: [FlightSpeed: NSMenuItem] = [:]
    private var colorItems: [BannerColor: NSMenuItem] = [:]
    private var calendarsMenuItem: NSMenuItem!
    private var signOutItem: NSMenuItem!
    private var calendars: [CalendarInfo] = []

    private let statusLabel = NSMenuItem(title: "Not connected", action: nil, keyEquivalent: "")
    private let nextTriggerLabel = NSMenuItem(title: "No upcoming reminders", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")

    init(
        onTestAnimation: @escaping () -> Void,
        onToggleEnabled: @escaping () -> Void = {},
        onReconnect: @escaping () -> Void = {},
        onSignOut: @escaping () -> Void = {},
        onRefresh: @escaping () -> Void = {},
        onCalendarsChanged: @escaping () -> Void = {},
        speedStore: FlightSpeedStoring = UserDefaultsFlightSpeedStore(),
        colorStore: BannerColorStoring = UserDefaultsBannerColorStore(),
        calendarSelectionStore: CalendarSelectionStoring = UserDefaultsCalendarSelectionStore()
    ) {
        self.onTestAnimation = onTestAnimation
        self.onToggleEnabled = onToggleEnabled
        self.onReconnect = onReconnect
        self.onSignOut = onSignOut
        self.onRefresh = onRefresh
        self.onCalendarsChanged = onCalendarsChanged
        self.speedStore = speedStore
        self.colorStore = colorStore
        self.calendarSelectionStore = calendarSelectionStore
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "airplane",
            accessibilityDescription: "cal-reminder"
        )
        buildMenu()
    }

    /// Reflects the coordinator's `AppState` in the menu (RF-06 status + next Trigger +
    /// RF-10 Calendars submenu).
    func render(_ state: AppState) {
        switch state.connectionStatus {
        case .connected(let email):
            statusLabel.title = email.map { "Connected as \($0)" } ?? "Connected"
        case .connecting:
            statusLabel.title = "Connecting…"
        case .disconnected:
            statusLabel.title = "Not connected"
        case .needsReauth:
            statusLabel.title = "Reconnect needed"
        }
        signOutItem.isHidden = state.connectionStatus == .disconnected

        toggleItem.title = state.enabled ? "Pause" : "Resume"

        // The refresh control (RF-12) only replaces the empty-state row — once a Trigger is
        // upcoming, this row goes back to being a plain status label.
        if let next = state.nextTrigger {
            let time = DateFormatter.localizedString(from: next.startDate, dateStyle: .none, timeStyle: .short)
            nextTriggerLabel.title = "Next: \(next.eventTitle) \(time)"
            nextTriggerLabel.image = nil
            nextTriggerLabel.action = nil
            nextTriggerLabel.target = nil
        } else if state.refreshing {
            nextTriggerLabel.title = "Refreshing…"
            nextTriggerLabel.image = nil
            nextTriggerLabel.action = nil
            nextTriggerLabel.target = nil
        } else {
            nextTriggerLabel.title = "No upcoming reminders"
            nextTriggerLabel.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
            nextTriggerLabel.action = #selector(handleRefresh)
            nextTriggerLabel.target = self
        }
        nextTriggerLabel.isEnabled = state.nextTrigger == nil && !state.refreshing

        calendars = state.calendars
        rebuildCalendarsSubmenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        statusLabel.isEnabled = false
        menu.addItem(statusLabel)
        menu.addItem(nextTriggerLabel)
        menu.addItem(.separator())

        toggleItem.action = #selector(handleToggleEnabled)
        toggleItem.target = self
        menu.addItem(toggleItem)

        let testItem = NSMenuItem(
            title: "Test animation",
            action: #selector(handleTestAnimation),
            keyEquivalent: ""
        )
        testItem.target = self
        menu.addItem(testItem)

        menu.addItem(flightSpeedMenuItem())
        menu.addItem(bannerColorMenuItem())

        calendarsMenuItem = NSMenuItem(title: "Calendars", action: nil, keyEquivalent: "")
        calendarsMenuItem.submenu = NSMenu()
        menu.addItem(calendarsMenuItem)

        let reconnectItem = NSMenuItem(
            title: "Reconnect Google",
            action: #selector(handleReconnect),
            keyEquivalent: ""
        )
        reconnectItem.target = self
        menu.addItem(reconnectItem)

        signOutItem = NSMenuItem(
            title: "Sign out of Google",
            action: #selector(handleSignOut),
            keyEquivalent: ""
        )
        signOutItem.target = self
        signOutItem.isHidden = true
        menu.addItem(signOutItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    /// "Flight Speed" submenu with the 3 presets (RF-07); the current preset is checked.
    private func flightSpeedMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        let currentSpeed = speedStore.flightSpeed

        for speed in FlightSpeed.allCases {
            let item = NSMenuItem(
                title: speed.displayName,
                action: #selector(handleSelectSpeed(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = speed
            item.state = speed == currentSpeed ? .on : .off
            speedItems[speed] = item
            submenu.addItem(item)
        }

        let speedMenuItem = NSMenuItem(title: "Flight Speed", action: nil, keyEquivalent: "")
        speedMenuItem.submenu = submenu
        return speedMenuItem
    }

    /// "Banner Color" submenu with the color presets (RF-07); the current preset is checked.
    private func bannerColorMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        let currentColor = colorStore.bannerColor

        for color in BannerColor.allCases {
            let item = NSMenuItem(
                title: color.displayName,
                action: #selector(handleSelectColor(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = color
            item.state = color == currentColor ? .on : .off
            colorItems[color] = item
            submenu.addItem(item)
        }

        let colorMenuItem = NSMenuItem(title: "Banner Color", action: nil, keyEquivalent: "")
        colorMenuItem.submenu = submenu
        return colorMenuItem
    }

    /// Rebuilds the "Calendars" submenu (RF-10) from `calendars`, one checkbox each,
    /// checked when effectively selected. Called from `render(_:)` so it always reflects
    /// the latest Poll.
    private func rebuildCalendarsSubmenu() {
        let submenu = NSMenu()
        let allIds = Set(calendars.map(\.id))

        if calendars.isEmpty {
            let placeholder = NSMenuItem(title: "No Calendars yet", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            submenu.addItem(placeholder)
        } else {
            for calendar in calendars {
                let isChecked = calendarSelectionStore.isSelected(calendar.id, within: allIds)
                let item = NSMenuItem()
                item.view = CalendarCheckboxView(title: calendar.title, isChecked: isChecked) { [weak self] isOn in
                    guard let self else { return }
                    calendarSelectionStore.setSelected(calendar.id, isOn, within: allIds)
                    onCalendarsChanged()
                }
                submenu.addItem(item)
            }
        }

        calendarsMenuItem.submenu = submenu
    }

    @objc private func handleTestAnimation() {
        onTestAnimation()
    }

    @objc private func handleToggleEnabled() {
        onToggleEnabled()
    }

    @objc private func handleReconnect() {
        onReconnect()
    }

    @objc private func handleSignOut() {
        onSignOut()
    }

    @objc private func handleRefresh() {
        onRefresh()
    }

    @objc private func handleSelectSpeed(_ sender: NSMenuItem) {
        guard let selected = sender.representedObject as? FlightSpeed else { return }
        speedStore.flightSpeed = selected
        for (speed, item) in speedItems {
            item.state = speed == selected ? .on : .off
        }
    }

    @objc private func handleSelectColor(_ sender: NSMenuItem) {
        guard let selected = sender.representedObject as? BannerColor else { return }
        colorStore.bannerColor = selected
        for (color, item) in colorItems {
            item.state = color == selected ? .on : .off
        }
    }
}
