import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenuController: StatusMenuController?
    private var coordinator: AppCoordinator?
    private let flightSpeedStore = UserDefaultsFlightSpeedStore()
    private let skipOnClickStore = UserDefaultsSkipOnClickStore()
    private let reminderSettingsStore = UserDefaultsReminderSettingsStore()
    private let telemetrySettingsStore = UserDefaultsTelemetrySettingsStore()
    private var telemetryClient: TelemetryClient?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let updateConfiguration = UpdateConfiguration.make(
            feedURL: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            publicKey: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        )
        let updateController = UpdateController(configuration: updateConfiguration)

        // The first-launch notice runs synchronously, before the client's timer is ever
        // started, so nothing can be sent before the user has seen it (RF-17).
        let telemetryConfiguration = TelemetryConfiguration.make(
            endpoint: Bundle.main.object(forInfoDictionaryKey: "TelemetryEndpoint") as? String,
            key: Bundle.main.object(forInfoDictionaryKey: "TelemetryKey") as? String
        )
        if let telemetryConfiguration {
            TelemetryFirstLaunchNotice.presentIfNeeded(settingsStore: telemetrySettingsStore)
            let client = TelemetryClient(configuration: telemetryConfiguration, settingsStore: telemetrySettingsStore)
            telemetryClient = client
        }

        let overlayPresenter = OverlayPresenter(
            animator: DefaultOverlayAnimator(speedStore: flightSpeedStore, skipOnClickStore: skipOnClickStore)
        )

        let accountRegistry = Self.makeAccountRegistry(reminderSettingsStore: reminderSettingsStore)
        let scheduler = Scheduler(onFire: { [telemetryClient] trigger in
            // Only a Trigger that actually fired reaches here — the test animation is enqueued
            // directly by AppCoordinator.testAnimation() and never goes through the Scheduler,
            // so it never counts (SPEC-023).
            telemetryClient?.recordPlaneFlown()
            telemetryClient?.recordActiveToday()
            Task { await overlayPresenter.enqueue(trigger) }
        })

        let coordinator = AppCoordinator(
            accounts: accountRegistry,
            scheduler: scheduler,
            overlay: overlayPresenter
        )
        coordinator.onWake = { [telemetryClient] in
            telemetryClient?.recordActiveToday()
        }
        self.coordinator = coordinator

        let statusMenuController = StatusMenuController(
            onTestAnimation: { [weak coordinator] in
                coordinator?.testAnimation()
            },
            onToggleEnabled: { [weak coordinator] in
                coordinator?.toggleEnabled()
            },
            onReconnect: { [weak coordinator] accountId in
                coordinator?.reconnect(accountId: accountId)
            },
            onSignOut: { [weak coordinator] accountId in
                coordinator?.signOut(accountId: accountId)
            },
            onRefresh: { [weak coordinator] in
                coordinator?.refreshNow()
            },
            onCalendarsChanged: { [weak coordinator] in
                coordinator?.calendarsChanged()
            },
            onAddAccount: { [weak coordinator] in
                coordinator?.addAccount()
            },
            onRemindersChanged: { [weak coordinator] in
                coordinator?.remindersChanged()
            },
            speedStore: flightSpeedStore,
            calendarSelectionStore: { UserDefaultsCalendarSelectionStore(accountId: $0) },
            skipOnClickStore: skipOnClickStore,
            reminderSettingsStore: reminderSettingsStore,
            updateController: updateController,
            telemetry: telemetryClient
        )
        self.statusMenuController = statusMenuController

        coordinator.onStateChange = { [weak statusMenuController] state in
            statusMenuController?.render(state)
        }

        coordinator.setUpdateStatus(
            updateController.isConfigured ? .configured(version: updateController.currentVersion) : .sourceBuild
        )

        telemetryClient?.recordInstallationIfChanged()
        telemetryClient?.recordActiveToday()
        telemetryClient?.start()

        guard GoogleOAuthConfig.bundled != nil else {
            coordinator.setOAuthConfigured(false)
            return
        }
        coordinator.start()
    }

    private static func makeAccountRegistry(reminderSettingsStore: ReminderSettingsStoring) -> AccountRegistry {
        let scopedTokenStore: (String) -> TokenStoring = {
            KeychainStore(account: KeychainStore.accountScopedKey($0))
        }
        let scopedCalendarSelectionStore: (String) -> CalendarSelectionStoring = {
            UserDefaultsCalendarSelectionStore(accountId: $0)
        }
        let provisionalAuthFactory: (TokenStoring) -> AccountAuthenticating = { tokenStore in
            AuthManager(
                config: GoogleOAuthConfig.bundled!,
                tokenStore: tokenStore,
                httpClient: URLSessionHTTPClient(),
                authorizationCodeProvider: LoopbackAuthorizationCodeProvider()
            )
        }
        let sessionFactory: (Account, TokenStoring, CalendarSelectionStoring) -> (auth: AccountAuthenticating, calendar: CalendarServicing) = { account, tokenStore, selectionStore in
            let auth = AuthManager(
                config: GoogleOAuthConfig.bundled!,
                tokenStore: tokenStore,
                httpClient: URLSessionHTTPClient(),
                authorizationCodeProvider: LoopbackAuthorizationCodeProvider()
            )
            let api = GoogleCalendarAPI(authManager: auth)
            let calendar = CalendarService(
                api: api,
                accountId: account.id,
                selectionStore: selectionStore,
                reminderSettingsStore: reminderSettingsStore
            )
            return (auth, calendar)
        }

        let factories = AccountSessionFactories(
            scopedTokenStore: scopedTokenStore,
            scopedCalendarSelectionStore: scopedCalendarSelectionStore,
            provisionalAuthFactory: provisionalAuthFactory,
            sessionFactory: sessionFactory
        )

        return AccountRegistry(
            accountStore: UserDefaultsAccountStore(),
            legacyMigration: LegacyAccountMigration(provisionalAuthFactory: provisionalAuthFactory),
            factories: factories
        )
    }
}
