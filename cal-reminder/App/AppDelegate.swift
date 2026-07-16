import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenuController: StatusMenuController?
    private var coordinator: AppCoordinator?
    private let flightSpeedStore = UserDefaultsFlightSpeedStore()
    private let calendarSelectionStore = UserDefaultsCalendarSelectionStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let overlayPresenter = OverlayPresenter(
            animator: DefaultOverlayAnimator(speedStore: flightSpeedStore)
        )

        let authManager = AuthManager(
            config: .embedded,
            tokenStore: KeychainStore(),
            httpClient: URLSessionHTTPClient(),
            authorizationCodeProvider: LoopbackAuthorizationCodeProvider()
        )
        let calendarAPI = GoogleCalendarAPI(authManager: authManager)
        let calendarService = CalendarService(api: calendarAPI, selectionStore: calendarSelectionStore)
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
            onSignOut: { [weak coordinator] in
                coordinator?.logout()
            },
            onRefresh: { [weak coordinator] in
                coordinator?.refreshNow()
            },
            onCalendarsChanged: { [weak coordinator] in
                coordinator?.calendarsChanged()
            },
            speedStore: flightSpeedStore,
            calendarSelectionStore: calendarSelectionStore
        )
        self.statusMenuController = statusMenuController

        coordinator.onStateChange = { [weak statusMenuController] state in
            statusMenuController?.render(state)
        }
        coordinator.start()
    }
}
