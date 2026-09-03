import Cocoa

/// A checkbox row for a "Calendars" submenu (RF-10). Uses a custom `NSMenuItem.view`
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

/// Bridges a Swift closure to Cocoa's target/action mechanism for a plain `NSMenuItem`
/// (Reconnect / Sign out / Add account). `NSMenuItem.target` isn't retained by the item, so
/// each instance is also stashed in `representedObject` to keep it alive for the item's
/// lifetime.
private final class MenuItemAction: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func perform() {
        action()
    }
}

/// The Accounts submenu's callbacks, bundled to keep `accountsMenu(for:...)`'s parameter
/// count within SwiftLint's `function_parameter_count` limit.
struct AccountsMenuActions {
    let onCalendarsChanged: () -> Void
    let onReconnect: (String) -> Void
    let onSignOut: (String) -> Void
    let onAddAccount: () -> Void
}

/// Builds the "Accounts" submenu (RF-14): one submenu per connected Account — its Calendars,
/// Reconnect, and Sign out — followed by "Add Google account…". A pure builder (no stored
/// state) so it can be exercised headlessly in tests.
enum AccountsMenuBuilder {
    /// One Account's "Calendars" submenu (RF-10): a checkbox per Calendar, checked when
    /// effectively selected.
    static func calendarsSubmenu(
        for account: AccountState,
        selectionStore: CalendarSelectionStoring,
        onCalendarsChanged: @escaping () -> Void
    ) -> NSMenu {
        let submenu = NSMenu()
        let allIds = Set(account.calendars.map(\.id))

        if account.calendars.isEmpty {
            let placeholder = NSMenuItem(title: "No Calendars yet", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            submenu.addItem(placeholder)
        } else {
            for calendar in account.calendars {
                let isChecked = selectionStore.isSelected(calendar.id, within: allIds)
                let item = NSMenuItem()
                item.view = CalendarCheckboxView(title: calendar.title, isChecked: isChecked) { isOn in
                    selectionStore.setSelected(calendar.id, isOn, within: allIds)
                    onCalendarsChanged()
                }
                submenu.addItem(item)
            }
        }

        return submenu
    }

    /// The full "Accounts" submenu, from every connected Account's state.
    static func accountsMenu(
        for accounts: [AccountState],
        selectionStore: (String) -> CalendarSelectionStoring,
        actions: AccountsMenuActions
    ) -> NSMenu {
        let menu = NSMenu()

        for account in accounts {
            menu.addItem(accountMenuItem(for: account, selectionStore: selectionStore(account.id), actions: actions))
        }

        if !accounts.isEmpty {
            menu.addItem(.separator())
        }
        menu.addItem(actionItem(title: "Add Google account…", action: actions.onAddAccount))

        return menu
    }

    private static func accountMenuItem(
        for account: AccountState,
        selectionStore: CalendarSelectionStoring,
        actions: AccountsMenuActions
    ) -> NSMenuItem {
        let accountItem = NSMenuItem()
        accountItem.title = account.connectionStatus == .needsReauth ? "⚠︎ \(account.label) — reconnect needed" : account.label

        let submenu = NSMenu()

        let calendarsItem = NSMenuItem(title: "Calendars", action: nil, keyEquivalent: "")
        calendarsItem.submenu = calendarsSubmenu(for: account, selectionStore: selectionStore, onCalendarsChanged: actions.onCalendarsChanged)
        submenu.addItem(calendarsItem)

        submenu.addItem(.separator())

        submenu.addItem(actionItem(title: "Reconnect") { actions.onReconnect(account.id) })
        submenu.addItem(actionItem(title: "Sign out") { actions.onSignOut(account.id) })

        accountItem.submenu = submenu
        return accountItem
    }

    private static func actionItem(title: String, action: @escaping () -> Void) -> NSMenuItem {
        let handler = MenuItemAction(action)
        let item = NSMenuItem(title: title, action: #selector(MenuItemAction.perform), keyEquivalent: "")
        item.target = handler
        item.representedObject = handler
        return item
    }
}
