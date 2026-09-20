import Cocoa

private final class TelemetryMenuItemAction: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invoke() {
        action()
    }
}

enum TelemetryMenuBuilder {
    static func items(for telemetry: TelemetryReporting?, onToggle: @escaping () -> Void) -> [NSMenuItem] {
        guard let telemetry, telemetry.isConfigured else {
            return []
        }

        let handler = TelemetryMenuItemAction(onToggle)
        let item = NSMenuItem(
            title: "Report anonymous usage",
            action: #selector(TelemetryMenuItemAction.invoke),
            keyEquivalent: ""
        )
        item.target = handler
        item.representedObject = handler
        item.state = telemetry.isEnabled ? .on : .off
        return [item]
    }
}
