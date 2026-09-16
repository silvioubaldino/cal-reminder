import AppKit

enum TelemetryNoticeChoice {
    case keepEnabled
    case turnOff
}

/// Shown once, before the first batch ever leaves the Mac (RF-17). Blocking by design — it
/// runs synchronously during launch, before `TelemetryClient.start()` schedules anything, so
/// there is no window in which telemetry could be sent before the user has seen this.
enum TelemetryFirstLaunchNotice {
    static func presentIfNeeded(
        settingsStore: TelemetrySettingsStoring,
        present: () -> TelemetryNoticeChoice = defaultPresenter
    ) {
        guard !settingsStore.noticeShown else { return }
        let choice = present()
        settingsStore.noticeShown = true
        if choice == .turnOff {
            settingsStore.enabled = false
        }
    }

    private static func defaultPresenter() -> TelemetryNoticeChoice {
        let alert = NSAlert()
        alert.messageText = "Anonymous usage reporting"
        alert.informativeText = """
        cal-reminder reports a few anonymous counts to the project — Reminder animations \
        played, whether the app was used today, and the app/macOS version. No calendar data, \
        no identifier of any kind. You can turn this off anytime from the menu bar.
        """
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Turn Off")
        return alert.runModal() == .alertFirstButtonReturn ? .keepEnabled : .turnOff
    }
}
