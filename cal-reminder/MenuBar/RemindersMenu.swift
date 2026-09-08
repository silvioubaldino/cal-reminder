import Cocoa

/// The "Reminders" menu item (RF-15): the Event's own Reminders on/off, then the fixed Extra
/// Reminder presets. Every toggle persists the selection, re-renders the item, and reports the
/// change so the upcoming Triggers can be rebuilt (AYD-008).
///
/// Owned by whoever builds the menu — `NSMenuItem.target` is weak, so this object must be held
/// for as long as the menu is on screen.
final class RemindersMenu: NSObject {
    let menuItem = NSMenuItem(title: "Reminders", action: nil, keyEquivalent: "")

    private let store: ReminderSettingsStoring
    private let onRemindersChanged: () -> Void
    private let inheritItem = NSMenuItem(title: "Event's own reminders", action: nil, keyEquivalent: "")
    private let warningItem = NSMenuItem(title: "⚠︎ No reminders selected — nothing will fly", action: nil, keyEquivalent: "")
    private var extraItems: [Int: NSMenuItem] = [:]

    init(store: ReminderSettingsStoring, onRemindersChanged: @escaping () -> Void) {
        self.store = store
        self.onRemindersChanged = onRemindersChanged
        super.init()

        let submenu = NSMenu()

        inheritItem.action = #selector(handleToggleInherit)
        inheritItem.target = self
        submenu.addItem(inheritItem)

        submenu.addItem(.separator())

        let header = NSMenuItem(title: "Always add:", action: nil, keyEquivalent: "")
        header.isEnabled = false
        submenu.addItem(header)

        for minutes in ReminderSettings.presetMinutes {
            let item = NSMenuItem(
                title: ReminderSettings.label(forMinutes: minutes),
                action: #selector(handleToggleExtra(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = minutes
            extraItems[minutes] = item
            submenu.addItem(item)
        }

        warningItem.isEnabled = false

        menuItem.submenu = submenu
        refresh()
    }

    /// Mirrors the stored selection into the menu: the parent title (so the selection reads
    /// without opening the submenu, AYD-008), the checkmarks, and the empty-selection warning.
    func refresh() {
        let settings = store.settings
        guard let submenu = menuItem.submenu else { return }

        menuItem.title = settings.menuTitle
        inheritItem.state = settings.inheritEventReminders ? .on : .off
        for (minutes, item) in extraItems {
            item.state = settings.extraMinutes.contains(minutes) ? .on : .off
        }

        let isShowingWarning = submenu.index(of: warningItem) >= 0
        if settings.isSilent, !isShowingWarning {
            submenu.addItem(.separator())
            submenu.addItem(warningItem)
        } else if !settings.isSilent, isShowingWarning {
            submenu.removeItem(warningItem)
            if let last = submenu.items.last, last.isSeparatorItem {
                submenu.removeItem(last)
            }
        }
    }

    @objc private func handleToggleInherit() {
        var settings = store.settings
        settings.inheritEventReminders.toggle()
        apply(settings)
    }

    @objc private func handleToggleExtra(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        var settings = store.settings
        if settings.extraMinutes.contains(minutes) {
            settings.extraMinutes.remove(minutes)
        } else {
            settings.extraMinutes.insert(minutes)
        }
        apply(settings)
    }

    private func apply(_ settings: ReminderSettings) {
        store.settings = settings
        refresh()
        onRemindersChanged()
    }
}
