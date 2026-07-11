import Cocoa

/// The `NSStatusItem` menu (RF-06). M0 skeleton: only "Test animation" and "Quit" are
/// wired; status/on-off/reconnect are placeholders until SPEC-003.
final class StatusMenuController {
    private let statusItem: NSStatusItem
    private let onTestAnimation: () -> Void

    init(onTestAnimation: @escaping () -> Void) {
        self.onTestAnimation = onTestAnimation
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

    @objc private func handleTestAnimation() {
        onTestAnimation()
    }
}
