import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenuController: StatusMenuController?
    private var coordinator: AppCoordinator?
    private let flightSpeedStore = UserDefaultsFlightSpeedStore()
    private let skipOnClickStore = UserDefaultsSkipOnClickStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let overlayPresenter = OverlayPresenter(
            animator: DefaultOverlayAnimator(speedStore: flightSpeedStore, skipOnClickStore: skipOnClickStore)
        )

        let accountRegistry = Self.makeAccountRegistry()
        let scheduler = Scheduler(onFire: { trigger in
            Task { await overlayPresenter.enqueue(trigger) }
        })

        let coordinator = AppCoordinator(
            accounts: accountRegistry,
            scheduler: scheduler,
            overlay: overlayPresenter
        )
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
            speedStore: flightSpeedStore,
            calendarSelectionStore: { UserDefaultsCalendarSelectionStore(accountId: $0) },
            skipOnClickStore: skipOnClickStore
        )
        self.statusMenuController = statusMenuController

        coordinator.onStateChange = { [weak statusMenuController] state in
            statusMenuController?.render(state)
        }
        coordinator.start()
    }

    /// Builds the real `AccountRegistry`: one `AuthManager` + `GoogleCalendarAPI` +
    /// `CalendarService` triple per connected Account, each backed by its own
    /// Account-scoped Keychain entry and Calendar-selection store (TDR-005).
    private static func makeAccountRegistry() -> AccountRegistry {
        let scopedTokenStore: (String) -> TokenStoring = {
            KeychainStore(account: KeychainStore.accountScopedKey($0))
        }
        let scopedCalendarSelectionStore: (String) -> CalendarSelectionStoring = {
            UserDefaultsCalendarSelectionStore(accountId: $0)
        }
        let provisionalAuthFactory: (TokenStoring) -> AccountAuthenticating = { tokenStore in
            AuthManager(
                config: .embedded,
                tokenStore: tokenStore,
                httpClient: URLSessionHTTPClient(),
                authorizationCodeProvider: LoopbackAuthorizationCodeProvider()
            )
        }
        let sessionFactory: (Account, TokenStoring, CalendarSelectionStoring) -> (auth: AccountAuthenticating, calendar: CalendarServicing) = { account, tokenStore, selectionStore in
            let auth = AuthManager(
                config: .embedded,
                tokenStore: tokenStore,
                httpClient: URLSessionHTTPClient(),
                authorizationCodeProvider: LoopbackAuthorizationCodeProvider()
            )
            let api = GoogleCalendarAPI(authManager: auth)
            let calendar = CalendarService(api: api, accountId: account.id, selectionStore: selectionStore)
            return (auth, calendar)
        }

        return AccountRegistry(
            accountStore: UserDefaultsAccountStore(),
            legacyMigration: LegacyAccountMigration(provisionalAuthFactory: provisionalAuthFactory),
            scopedTokenStore: scopedTokenStore,
            scopedCalendarSelectionStore: scopedCalendarSelectionStore,
            provisionalAuthFactory: provisionalAuthFactory,
            sessionFactory: sessionFactory
        )
    }
}
