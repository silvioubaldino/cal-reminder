import Cocoa

/// The `NSStatusItem` menu (RF-06): connection status, next upcoming Trigger, Pause/Resume,
/// test animation, Flight Speed, Reconnect Google, and Quit. `render(_:)` reflects the
/// `AppCoordinator`'s `AppState` after every change.
final class StatusMenuController {
    private let statusItem: NSStatusItem
    private let onTestAnimation: () -> Void
    private let onToggleEnabled: () -> Void
    private let onReconnect: () -> Void
    private let speedStore: FlightSpeedStoring
    private let colorStore: BannerColorStoring
    private var speedItems: [FlightSpeed: NSMenuItem] = [:]
    private var colorItems: [BannerColor: NSMenuItem] = [:]

    private let statusLabel = NSMenuItem(title: "Not connected", action: nil, keyEquivalent: "")
    private let nextTriggerLabel = NSMenuItem(title: "No upcoming reminders", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")

    init(
        onTestAnimation: @escaping () -> Void,
        onToggleEnabled: @escaping () -> Void = {},
        onReconnect: @escaping () -> Void = {},
        speedStore: FlightSpeedStoring = UserDefaultsFlightSpeedStore(),
        colorStore: BannerColorStoring = UserDefaultsBannerColorStore()
    ) {
        self.onTestAnimation = onTestAnimation
        self.onToggleEnabled = onToggleEnabled
        self.onReconnect = onReconnect
        self.speedStore = speedStore
        self.colorStore = colorStore
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "airplane",
            accessibilityDescription: "cal-reminder"
        )
        buildMenu()
    }

    /// Reflects the coordinator's `AppState` in the menu (RF-06 status + next Trigger).
    func render(_ state: AppState) {
        if state.connected, let email = state.userEmail {
            statusLabel.title = "Connected as \(email)"
        } else {
            statusLabel.title = state.connected ? "Connected" : "Not connected"
        }
        toggleItem.title = state.enabled ? "Pause" : "Resume"

        if let next = state.nextTrigger {
            let time = DateFormatter.localizedString(from: next.startDate, dateStyle: .none, timeStyle: .short)
            nextTriggerLabel.title = "Next: \(next.eventTitle) \(time)"
        } else {
            nextTriggerLabel.title = "No upcoming reminders"
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        statusLabel.isEnabled = false
        menu.addItem(statusLabel)
        nextTriggerLabel.isEnabled = false
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

        let reconnectItem = NSMenuItem(
            title: "Reconnect Google",
            action: #selector(handleReconnect),
            keyEquivalent: ""
        )
        reconnectItem.target = self
        menu.addItem(reconnectItem)

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

    @objc private func handleTestAnimation() {
        onTestAnimation()
    }

    @objc private func handleToggleEnabled() {
        onToggleEnabled()
    }

    @objc private func handleReconnect() {
        onReconnect()
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
