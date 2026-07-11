import Foundation

protocol GoogleCalendarAPIProtocol {
    /// `calendarList.list` — every Calendar in the connected account (RF-10). Keeps only
    /// entries whose `accessRole` can read Event details (owner | writer | reader).
    func listCalendars() async throws -> [GoogleCalendarListEntry]

    /// `events.list` on `calendarId`. Uses `syncToken` for incremental sync (RNF-06) when
    /// available, otherwise falls back to `timeMin`/`timeMax`. The response carries that
    /// Calendar's `defaultReminders` inline (RN-04).
    func listEvents(calendarId: String, timeMin: Date, timeMax: Date, syncToken: String?) async throws -> (events: [GoogleEvent], nextSyncToken: String?, defaultReminders: [GoogleCalendarDefaultReminder]?)
}

enum GoogleCalendarAPIError: Error {
    case unexpectedStatus(Int)
}

final class GoogleCalendarAPI: GoogleCalendarAPIProtocol {
    private let authManager: AuthManaging
    private let baseURL = URL(string: "https://www.googleapis.com/calendar/v3")!

    init(authManager: AuthManaging) {
        self.authManager = authManager
    }

    func listCalendars() async throws -> [GoogleCalendarListEntry] {
        let readableRoles: Set<String> = ["owner", "writer", "reader"]
        let data = try await get(baseURL.appendingPathComponent("users/me/calendarList"))
        let decoded = try JSONDecoder().decode(GoogleCalendarListResponse.self, from: data)
        let kept = decoded.items.filter { readableRoles.contains($0.accessRole) }
        print("[GoogleCalendarAPI] listCalendars: \(decoded.items.count) total, \(kept.count) readable → \(decoded.items.map { "\($0.id) (\($0.accessRole))" })")
        return kept
    }

    func listEvents(calendarId: String, timeMin: Date, timeMax: Date, syncToken: String?) async throws -> (events: [GoogleEvent], nextSyncToken: String?, defaultReminders: [GoogleCalendarDefaultReminder]?) {
        let encodedCalendarId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        var components = URLComponents(
            url: baseURL.appendingPathComponent("calendars/\(encodedCalendarId)/events"),
            resolvingAgainstBaseURL: false
        )!

        var query = [URLQueryItem(name: "singleEvents", value: "true")]
        if let syncToken {
            query.append(URLQueryItem(name: "syncToken", value: syncToken))
        } else {
            let formatter = ISO8601DateFormatter()
            query.append(URLQueryItem(name: "timeMin", value: formatter.string(from: timeMin)))
            query.append(URLQueryItem(name: "timeMax", value: formatter.string(from: timeMax)))
        }
        components.queryItems = query

        let data = try await get(components.url!)
        let decoded = try JSONDecoder().decode(GoogleEventsListResponse.self, from: data)
        return (decoded.items, decoded.nextSyncToken, decoded.defaultReminders)
    }

    private func get(_ url: URL) async throws -> Data {
        let (data, response) = try await authManager.authorizedRequest { token in
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return request
        }
        guard response.statusCode == 200 else {
            print("[GoogleCalendarAPI] GET \(url.absoluteString) → HTTP \(response.statusCode): \(String(data: data, encoding: .utf8) ?? "<non-utf8 body>")")
            throw GoogleCalendarAPIError.unexpectedStatus(response.statusCode)
        }
        return data
    }
}
