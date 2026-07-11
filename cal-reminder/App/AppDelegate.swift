import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenuController: StatusMenuController?
    private var coordinator: AppCoordinator?
    private let flightSpeedStore = UserDefaultsFlightSpeedStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let overlayPresenter = OverlayPresenter(
            animator: DefaultOverlayAnimator(speedStore: flightSpeedStore)
        )

        let config = (try? GoogleOAuthConfig.loadFromDisk())
            ?? GoogleOAuthConfig(clientID: "", clientSecret: "")
        let authManager = AuthManager(
            config: config,
            tokenStore: KeychainStore(),
            httpClient: URLSessionHTTPClient(),
            authorizationCodeProvider: LoopbackAuthorizationCodeProvider()
        )
        let calendarAPI = GoogleCalendarAPI(authManager: authManager)
        let calendarService = CalendarService(api: calendarAPI)
        let scheduler = Scheduler(onFire: { trigger in
            Task { await overlayPresenter.enqueue(trigger) }
        })

        let coordinator = AppCoordinator(
            auth: authManager,
            calendar: calendarService,
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
            onReconnect: { [weak coordinator] in
                coordinator?.reconnect()
            },
            speedStore: flightSpeedStore
        )
        self.statusMenuController = statusMenuController

        coordinator.onStateChange = { [weak statusMenuController] state in
            statusMenuController?.render(state)
        }
        coordinator.start()
    }
}
