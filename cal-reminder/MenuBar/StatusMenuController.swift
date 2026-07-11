import Cocoa

/// The `NSStatusItem` menu (RF-06). M0 skeleton: only "Test animation" and "Quit" are
/// wired; status/on-off/reconnect are placeholders until SPEC-003.
final class StatusMenuController {
    private let statusItem: NSStatusItem
    private let onTestAnimation: () -> Void
    private let speedStore: FlightSpeedStoring
    private var speedItems: [FlightSpeed: NSMenuItem] = [:]

    init(
        onTestAnimation: @escaping () -> Void,
        speedStore: FlightSpeedStoring = UserDefaultsFlightSpeedStore()
    ) {
        self.onTestAnimation = onTestAnimation
        self.speedStore = speedStore
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "airplane",
            accessibilityDescription: "cal-reminder"
        )
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        let statusLabel = NSMenuItem(title: "Not connected", action: nil, keyEquivalent: "")
        statusLabel.isEnabled = false
        menu.addItem(statusLabel)
        menu.addItem(.separator())

        let toggleItem = NSMenuItem(title: "Enabled", action: nil, keyEquivalent: "")
        toggleItem.isEnabled = false
        menu.addItem(toggleItem)

        let testItem = NSMenuItem(
            title: "Test animation",
            action: #selector(handleTestAnimation),
            keyEquivalent: ""
        )
        testItem.target = self
        menu.addItem(testItem)

        menu.addItem(flightSpeedMenuItem())

        let reconnectItem = NSMenuItem(title: "Reconnect Google", action: nil, keyEquivalent: "")
        reconnectItem.isEnabled = false
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

    @objc private func handleTestAnimation() {
        onTestAnimation()
    }

    @objc private func handleSelectSpeed(_ sender: NSMenuItem) {
        guard let selected = sender.representedObject as? FlightSpeed else { return }
        speedStore.flightSpeed = selected
        for (speed, item) in speedItems {
            item.state = speed == selected ? .on : .off
        }
    }
}
