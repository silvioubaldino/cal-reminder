import XCTest
@testable import cal_reminder

private final class FakeAuthManaging: AuthManaging {
    var isConnected = true
    var response: (Data, HTTPURLResponse) = (Data(), httpResponse(status: 200))
    private(set) var lastRequest: URLRequest?

    func connect(loginHint: String?) async throws {}
    func accessToken() async throws -> String { "access-token" }
    func identity() async throws -> Account { Account(id: "google:test", provider: .google, label: "user@example.com") }
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

        let calendars = try await api.listCalendars()

        XCTAssertEqual(Set(calendars.map(\.id)), ["primary", "shared", "readonly"])
    }

    func test_listCalendars_decodesTheCalendarColorWhenPresent() async throws {
        let auth = FakeAuthManaging()
        let json: [String: Any] = [
            "items": [
                ["id": "colored", "summary": "Colored", "accessRole": "owner", "backgroundColor": "#0b8043"],
                ["id": "plain", "summary": "Plain", "accessRole": "owner"]
            ]
        ]
        auth.response = (try! JSONSerialization.data(withJSONObject: json), httpResponse(status: 200))
        let api = GoogleCalendarAPI(authManager: auth)

        let calendars = try await api.listCalendars()

        XCTAssertEqual(calendars.first(where: { $0.id == "colored" })?.backgroundColor, "#0b8043")
        XCTAssertNil(calendars.first(where: { $0.id == "plain" })?.backgroundColor)
    }

    func test_listEvents_buildsPathForGivenCalendarId() async throws {
        let auth = FakeAuthManaging()
        let json: [String: Any] = ["items": []]
        auth.response = (try! JSONSerialization.data(withJSONObject: json), httpResponse(status: 200))
        let api = GoogleCalendarAPI(authManager: auth)

        _ = try await api.listEvents(
            calendarId: "team@group.calendar.google.com",
            timeMin: Date(timeIntervalSince1970: 0),
            timeMax: Date(timeIntervalSince1970: 3600),
            syncToken: nil
        )

        let path = auth.lastRequest?.url?.path ?? ""
        XCTAssertTrue(path.contains("calendars/team@group.calendar.google.com/events"), path)
    }

    func test_listEvents_decodesACancelledEntryWithNoStart() async throws {
        // A cancelled Event in an incremental delta carries only `id` and `status`, no `start`
        // (AYD-011) — decoding it must not throw.
        let auth = FakeAuthManaging()
        let json: [String: Any] = [
            "items": [
                ["id": "evt-gone", "status": "cancelled"]
            ],
            "nextSyncToken": "token-after-delta"
        ]
        auth.response = (try! JSONSerialization.data(withJSONObject: json), httpResponse(status: 200))
        let api = GoogleCalendarAPI(authManager: auth)

        let result = try await api.listEvents(calendarId: "primary", timeMin: Date(), timeMax: Date(), syncToken: "stale-token")

        XCTAssertEqual(result.events.first?.id, "evt-gone")
        XCTAssertEqual(result.events.first?.status, "cancelled")
        XCTAssertNil(result.events.first?.start)
        XCTAssertEqual(result.nextSyncToken, "token-after-delta")
    }

    func test_listEvents_throwsUnexpectedStatusOnNon200() async {
        let auth = FakeAuthManaging()
        auth.response = (Data(), httpResponse(status: 410))
        let api = GoogleCalendarAPI(authManager: auth)

        do {
            _ = try await api.listEvents(calendarId: "primary", timeMin: Date(), timeMax: Date(), syncToken: "stale")
            XCTFail("expected unexpectedStatus to be thrown")
        } catch GoogleCalendarAPIError.unexpectedStatus(410) {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
