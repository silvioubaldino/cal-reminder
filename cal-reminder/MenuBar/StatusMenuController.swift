import Cocoa

final class StatusMenuController {
    private let statusItem: NSStatusItem
    private let onTestAnimation: () -> Void
    private let onToggleEnabled: () -> Void
    private let onReconnect: (String) -> Void
    private let onSignOut: (String) -> Void
    private let onRefresh: () -> Void
    private let onCalendarsChanged: () -> Void
    private let onAddAccount: () -> Void
    private let speedStore: FlightSpeedStoring
    private let colorStore: BannerColorStoring
    private let matchCalendarColorStore: MatchCalendarColorStoring
    private let calendarSelectionStore: (String) -> CalendarSelectionStoring
    private let skipOnClickStore: SkipOnClickStoring
    private var speedItems: [FlightSpeed: NSMenuItem] = [:]
    private var colorItems: [BannerColor: NSMenuItem] = [:]
    private var matchCalendarColorItem: NSMenuItem!
    private var accountsMenuItem: NSMenuItem!
    private var skipOnClickItem: NSMenuItem!

    private let statusLabel = NSMenuItem(title: "Not connected", action: nil, keyEquivalent: "")
    private let nextTriggerLabel = NSMenuItem(title: "No upcoming reminders", action: nil, keyEquivalent: "")
    private let refreshItem = NSMenuItem(title: "Refresh now", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")

    init(
        onTestAnimation: @escaping () -> Void,
        onToggleEnabled: @escaping () -> Void = {},
        onReconnect: @escaping (String) -> Void = { _ in },
        onSignOut: @escaping (String) -> Void = { _ in },
        onRefresh: @escaping () -> Void = {},
        onCalendarsChanged: @escaping () -> Void = {},
        onAddAccount: @escaping () -> Void = {},
        speedStore: FlightSpeedStoring = UserDefaultsFlightSpeedStore(),
        colorStore: BannerColorStoring = UserDefaultsBannerColorStore(),
        matchCalendarColorStore: MatchCalendarColorStoring = UserDefaultsMatchCalendarColorStore(),
        calendarSelectionStore: @escaping (String) -> CalendarSelectionStoring = { UserDefaultsCalendarSelectionStore(accountId: $0) },
        skipOnClickStore: SkipOnClickStoring = UserDefaultsSkipOnClickStore()
    ) {
        self.onTestAnimation = onTestAnimation
        self.onToggleEnabled = onToggleEnabled
        self.onReconnect = onReconnect
        self.onSignOut = onSignOut
        self.onRefresh = onRefresh
        self.onCalendarsChanged = onCalendarsChanged
        self.onAddAccount = onAddAccount
        self.speedStore = speedStore
        self.colorStore = colorStore
        self.matchCalendarColorStore = matchCalendarColorStore
        self.calendarSelectionStore = calendarSelectionStore
        self.skipOnClickStore = skipOnClickStore
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "airplane",
            accessibilityDescription: "cal-reminder"
        )
        buildMenu()
    }

    func render(_ state: AppState) {
        statusLabel.title = state.statusTitle

        toggleItem.title = state.enabled ? "Pause" : "Resume"

        if let next = state.nextTrigger {
            let time = DateFormatter.localizedString(from: next.startDate, dateStyle: .none, timeStyle: .short)
            nextTriggerLabel.title = "Next: \(next.eventTitle) \(time)"
        } else {
            nextTriggerLabel.title = "No upcoming reminders"
        }

        refreshItem.title = state.refreshing ? "Refreshing…" : "Refresh now"
        refreshItem.isEnabled = !state.refreshing

        accountsMenuItem.submenu = AccountsMenuBuilder.accountsMenu(
            for: state.accounts,
            selectionStore: calendarSelectionStore,
            actions: AccountsMenuActions(
                onCalendarsChanged: onCalendarsChanged,
                onReconnect: onReconnect,
                onSignOut: onSignOut,
                onAddAccount: onAddAccount
            )
        )
    }

    private func buildMenu() {
        let menu = NSMenu()

        statusLabel.isEnabled = false
        menu.addItem(statusLabel)
        nextTriggerLabel.isEnabled = false
        menu.addItem(nextTriggerLabel)

        refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        refreshItem.action = #selector(handleRefresh)
        refreshItem.target = self
        menu.addItem(refreshItem)

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
        menu.addItem(skipOnClickMenuItem())

        accountsMenuItem = NSMenuItem(title: "Accounts", action: nil, keyEquivalent: "")
        accountsMenuItem.submenu = NSMenu()
        menu.addItem(accountsMenuItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

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

    private func bannerColorMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        let currentColor = colorStore.bannerColor

        let matchItem = NSMenuItem(
            title: "Match calendar color",
            action: #selector(handleToggleMatchCalendarColor),
            keyEquivalent: ""
        )
        matchItem.target = self
        matchItem.state = matchCalendarColorStore.matchCalendarColor ? .on : .off
        matchCalendarColorItem = matchItem
        submenu.addItem(matchItem)
        submenu.addItem(.separator())

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

    private func skipOnClickMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Click anywhere to skip",
            action: #selector(handleToggleSkipOnClick),
            keyEquivalent: ""
        )
        item.target = self
        item.state = skipOnClickStore.skipOnClick ? .on : .off
        skipOnClickItem = item
        return item
    }

    @objc private func handleTestAnimation() {
        onTestAnimation()
    }

    @objc private func handleToggleEnabled() {
        onToggleEnabled()
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

    @objc private func handleToggleMatchCalendarColor() {
        let newValue = !matchCalendarColorStore.matchCalendarColor
        matchCalendarColorStore.matchCalendarColor = newValue
        matchCalendarColorItem.state = newValue ? .on : .off
    }

    @objc private func handleToggleSkipOnClick() {
        let newValue = !skipOnClickStore.skipOnClick
        skipOnClickStore.skipOnClick = newValue
        skipOnClickItem.state = newValue ? .on : .off
    }
}
