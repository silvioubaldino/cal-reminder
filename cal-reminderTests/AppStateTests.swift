import XCTest
@testable import cal_reminder

final class AppStateTests: XCTestCase {
    private func account(_ id: String, label: String, status: ConnectionStatus) -> AccountState {
        AccountState(id: id, label: label, connectionStatus: status)
    }

    func test_statusTitle_noAccounts() {
        let state = AppState()

        XCTAssertEqual(state.statusTitle, "Not connected")
    }

    func test_statusTitle_oneConnectedAccount() {
        var state = AppState()
        state.accounts = [account("google:a", label: "a@example.com", status: .connected)]

        XCTAssertEqual(state.statusTitle, "Connected as a@example.com")
    }

    func test_statusTitle_oneConnectingAccount() {
        var state = AppState()
        state.accounts = [account("google:a", label: "a@example.com", status: .connecting)]

        XCTAssertEqual(state.statusTitle, "Connecting…")
    }

    func test_statusTitle_oneAccountNeedingReauth() {
        var state = AppState()
        state.accounts = [account("google:a", label: "a@example.com", status: .needsReauth)]

        XCTAssertEqual(state.statusTitle, "Reconnect needed")
    }

    func test_statusTitle_multipleConnectedAccounts() {
        var state = AppState()
        state.accounts = [
            account("google:a", label: "a@example.com", status: .connected),
            account("google:b", label: "b@example.com", status: .connected)
        ]

        XCTAssertEqual(state.statusTitle, "Connected · 2 accounts")
    }

    func test_statusTitle_multipleAccountsAllConnecting() {
        var state = AppState()
        state.accounts = [
            account("google:a", label: "a@example.com", status: .connecting),
            account("google:b", label: "b@example.com", status: .connecting)
        ]

        XCTAssertEqual(state.statusTitle, "Connecting…")
    }

    func test_statusTitle_oneOfSeveralNeedsReconnecting() {
        var state = AppState()
        state.accounts = [
            account("google:a", label: "a@example.com", status: .connected),
            account("google:b", label: "b@example.com", status: .needsReauth)
        ]

        XCTAssertEqual(state.statusTitle, "2 accounts · 1 needs reconnecting")
    }

    func test_statusTitle_multipleAccountsNeedReconnecting() {
        var state = AppState()
        state.accounts = [
            account("google:a", label: "a@example.com", status: .needsReauth),
            account("google:b", label: "b@example.com", status: .needsReauth),
            account("google:c", label: "c@example.com", status: .connected)
        ]

        XCTAssertEqual(state.statusTitle, "3 accounts · 2 need reconnecting")
    }

    func test_statusTitle_oauthNotConfigured_noAccounts() {
        var state = AppState()
        state.oauthConfigured = false

        XCTAssertEqual(state.statusTitle, "Setup needed — no Google client")
    }

    func test_statusTitle_oauthNotConfigured_winsOverConnectedAccounts() {
        var state = AppState()
        state.oauthConfigured = false
        state.accounts = [account("google:a", label: "a@example.com", status: .connected)]

        XCTAssertEqual(state.statusTitle, "Setup needed — no Google client")
    }

    func test_updateStatus_defaultsToSourceBuild() {
        let state = AppState()

        XCTAssertEqual(state.updateStatus, .sourceBuild)
    }

    func test_updateStatus_configured_carriesVersion() {
        var state = AppState()
        state.updateStatus = .configured(version: "1.2.0")

        XCTAssertEqual(state.updateStatus, .configured(version: "1.2.0"))
    }
}
