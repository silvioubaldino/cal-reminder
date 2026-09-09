import AppKit
import Sparkle

protocol Updating: AnyObject {
    var isConfigured: Bool { get }
    var automaticallyChecks: Bool { get set }
    var currentVersion: String { get }
    func checkForUpdates()
}

struct UpdateConfiguration {
    let feedURL: String
    let publicKey: String

    static func make(feedURL: String?, publicKey: String?) -> UpdateConfiguration? {
        guard
            let feedURL = feedURL?.trimmingCharacters(in: .whitespacesAndNewlines), !feedURL.isEmpty,
            let publicKey = publicKey?.trimmingCharacters(in: .whitespacesAndNewlines), !publicKey.isEmpty
        else {
            return nil
        }
        return UpdateConfiguration(feedURL: feedURL, publicKey: publicKey)
    }
}

protocol SparkleUpdating: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    func checkForUpdates()
}

extension SPUUpdater: SparkleUpdating {}

final class UpdateController: Updating {
    let isConfigured: Bool
    private let settingsStore: UpdateSettingsStoring
    private let updater: SparkleUpdating?
    private let activateApp: () -> Void
    private var retainedUpdaterController: SPUStandardUpdaterController?

    convenience init(
        configuration: UpdateConfiguration?,
        settingsStore: UpdateSettingsStoring = UserDefaultsUpdateSettingsStore()
    ) {
        guard configuration != nil else {
            self.init(updater: nil, settingsStore: settingsStore)
            return
        }

        let updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.init(updater: updaterController.updater, settingsStore: settingsStore)
        retainedUpdaterController = updaterController
    }

    init(
        updater: SparkleUpdating?,
        settingsStore: UpdateSettingsStoring = UserDefaultsUpdateSettingsStore(),
        activateApp: @escaping () -> Void = { NSApp.activate(ignoringOtherApps: true) }
    ) {
        self.updater = updater
        self.isConfigured = updater != nil
        self.settingsStore = settingsStore
        self.activateApp = activateApp
        updater?.automaticallyChecksForUpdates = settingsStore.automaticallyChecks
    }

    var automaticallyChecks: Bool {
        get { settingsStore.automaticallyChecks }
        set {
            settingsStore.automaticallyChecks = newValue
            updater?.automaticallyChecksForUpdates = newValue
        }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    func checkForUpdates() {
        activateApp()
        updater?.checkForUpdates()
    }
}
