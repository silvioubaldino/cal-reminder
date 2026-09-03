import XCTest
@testable import cal_reminder

final class AppStateTests: XCTestCase {
    private func account(_ id: String, label: String, status: ConnectionStatus) -> AccountState {
        AccountState(id: id, label: label, connectionStatus: status)
    }

    func test_statusTitle_noAccounts() {
        // Arrange
        let state = AppState()

        // Act / Assert
        XCTAssertEqual(state.statusTitle, "Not connected")
    }

    func test_statusTitle_oneConnectedAccount() {
        // Arrange
        var state = AppState()
        state.accounts = [account("google:a", label: "a@example.com", status: .connected)]

        // Act / Assert
        XCTAssertEqual(state.statusTitle, "Connected as a@example.com")
    }

    func test_statusTitle_oneConnectingAccount() {
        // Arrange
        var state = AppState()
        state.accounts = [account("google:a", label: "a@example.com", status: .connecting)]

        // Act / Assert
        XCTAssertEqual(state.statusTitle, "Connecting…")
    }

    func test_statusTitle_oneAccountNeedingReauth() {
        // Arrange
        var state = AppState()
        state.accounts = [account("google:a", label: "a@example.com", status: .needsReauth)]

        // Act / Assert
        XCTAssertEqual(state.statusTitle, "Reconnect needed")
    }

    func test_statusTitle_multipleConnectedAccounts() {
        // Arrange (RF-14)
        var state = AppState()
        state.accounts = [
            account("google:a", label: "a@example.com", status: .connected),
            account("google:b", label: "b@example.com", status: .connected)
        ]

        // Act / Assert
        XCTAssertEqual(state.statusTitle, "Connected · 2 accounts")
    }

    func test_statusTitle_multipleAccountsAllConnecting() {
        // Arrange
        var state = AppState()
        state.accounts = [
            account("google:a", label: "a@example.com", status: .connecting),
            account("google:b", label: "b@example.com", status: .connecting)
        ]

        // Act / Assert
        XCTAssertEqual(state.statusTitle, "Connecting…")
    }

    func test_statusTitle_oneOfSeveralNeedsReconnecting() {
        // Arrange
        var state = AppState()
        state.accounts = [
            account("google:a", label: "a@example.com", status: .connected),
            account("google:b", label: "b@example.com", status: .needsReauth)
        ]

        // Act / Assert
        XCTAssertEqual(state.statusTitle, "2 accounts · 1 needs reconnecting")
    }

    func test_statusTitle_multipleAccountsNeedReconnecting() {
        // Arrange
        var state = AppState()
        state.accounts = [
            account("google:a", label: "a@example.com", status: .needsReauth),
            account("google:b", label: "b@example.com", status: .needsReauth),
            account("google:c", label: "c@example.com", status: .connected)
        ]

        // Act / Assert
        XCTAssertEqual(state.statusTitle, "3 accounts · 2 need reconnecting")
    }
}
