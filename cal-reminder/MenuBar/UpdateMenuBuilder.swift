import Cocoa

private final class UpdateMenuItemAction: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invoke() {
        action()
    }
}

enum UpdateMenuBuilder {
    static func items(
        for updater: Updating,
        onCheckForUpdates: @escaping () -> Void,
        onToggleAutomaticChecks: @escaping () -> Void
    ) -> [NSMenuItem] {
        guard updater.isConfigured else {
            let item = NSMenuItem(title: "Updates: source build", action: nil, keyEquivalent: "")
            item.isEnabled = false
            return [item]
        }

        let versionItem = NSMenuItem(title: "cal-reminder \(updater.currentVersion)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false

        let checkItem = actionItem(title: "Check for updates…", action: onCheckForUpdates)

        let autoItem = actionItem(title: "Check automatically", action: onToggleAutomaticChecks)
        autoItem.state = updater.automaticallyChecks ? .on : .off

        return [versionItem, checkItem, autoItem]
    }

    private static func actionItem(title: String, action: @escaping () -> Void) -> NSMenuItem {
        let handler = UpdateMenuItemAction(action)
        let item = NSMenuItem(title: title, action: #selector(UpdateMenuItemAction.invoke), keyEquivalent: "")
        item.target = handler
        item.representedObject = handler
        return item
    }
}
