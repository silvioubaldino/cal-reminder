import XCTest
@testable import cal_reminder

/// Replays a scripted `(Data, HTTPURLResponse)` and records the request `authorizedRequest`
/// built, so `GoogleCalendarAPI` can be tested without a real network or `AuthManager`.
private final class FakeAuthManaging: AuthManaging {
    var isConnected = true
    var response: (Data, HTTPURLResponse) = (Data(), httpResponse(status: 200))
    private(set) var lastRequest: URLRequest?

    func connect() async throws {}
    func accessToken() async throws -> String { "access-token" }
    func userEmail() async throws -> String { "user@example.com" }
    func disconnect() async {}

    func authorizedRequest(_ makeRequest: (String) -> URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = makeRequest("access-token")
        return response
    }
}

private func httpResponse(status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://www.googleapis.com/calendar/v3")!, statusCode: status, httpVersion: nil, headerFields: nil)!
}

final class GoogleCalendarAPITests: XCTestCase {
    func test_listCalendars_keepsOnlyReadableAccessRoles() async throws {
        // Arrange
        let auth = FakeAuthManaging()
        let json: [String: Any] = [
            "items": [
                ["id": "primary", "summary": "Primary", "primary": true, "accessRole": "owner"],
                ["id": "shared", "summary": "Shared", "accessRole": "writer"],
                ["id": "readonly", "summary": "Read-only", "accessRole": "reader"],
                ["id": "freebusy", "summary": "Free/busy only", "accessRole": "freeBusyReader"]
            ]
        ]
        auth.response = (try! JSONSerialization.data(withJSONObject: json), httpResponse(status: 200))
        let api = GoogleCalendarAPI(authManager: auth)

        // Act
        let calendars = try await api.listCalendars()

        // Assert
        XCTAssertEqual(Set(calendars.map(\.id)), ["primary", "shared", "readonly"])
    }

    func test_listCalendars_decodesTheCalendarColorWhenPresent() async throws {
        // Arrange (RF-13; `backgroundColor` is optional — a response without it must decode)
        let auth = FakeAuthManaging()
        let json: [String: Any] = [
            "items": [
                ["id": "colored", "summary": "Colored", "accessRole": "owner", "backgroundColor": "#0b8043"],
                ["id": "plain", "summary": "Plain", "accessRole": "owner"]
            ]
        ]
        auth.response = (try! JSONSerialization.data(withJSONObject: json), httpResponse(status: 200))
        let api = GoogleCalendarAPI(authManager: auth)

        // Act
        let calendars = try await api.listCalendars()

        // Assert
        XCTAssertEqual(calendars.first(where: { $0.id == "colored" })?.backgroundColor, "#0b8043")
        XCTAssertNil(calendars.first(where: { $0.id == "plain" })?.backgroundColor)
    }

    func test_listEvents_buildsPathForGivenCalendarId() async throws {
        // Arrange
        let auth = FakeAuthManaging()
        let json: [String: Any] = ["items": []]
        auth.response = (try! JSONSerialization.data(withJSONObject: json), httpResponse(status: 200))
        let api = GoogleCalendarAPI(authManager: auth)

        // Act
        _ = try await api.listEvents(
            calendarId: "team@group.calendar.google.com",
            timeMin: Date(timeIntervalSince1970: 0),
            timeMax: Date(timeIntervalSince1970: 3600),
            syncToken: nil
        )

        // Assert
        let path = auth.lastRequest?.url?.path ?? ""
        XCTAssertTrue(path.contains("calendars/team@group.calendar.google.com/events"), path)
    }

    func test_listEvents_throwsUnexpectedStatusOnNon200() async {
        // Arrange
        let auth = FakeAuthManaging()
        auth.response = (Data(), httpResponse(status: 410))
        let api = GoogleCalendarAPI(authManager: auth)

        // Act / Assert
        do {
            _ = try await api.listEvents(calendarId: "primary", timeMin: Date(), timeMax: Date(), syncToken: "stale")
            XCTFail("expected unexpectedStatus to be thrown")
        } catch GoogleCalendarAPIError.unexpectedStatus(410) {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
