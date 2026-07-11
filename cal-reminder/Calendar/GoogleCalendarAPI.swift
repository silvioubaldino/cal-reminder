import Foundation

protocol GoogleCalendarAPIProtocol {
    /// `events.list` on the primary calendar. Uses `syncToken` for incremental sync
    /// (RNF-06) when available, otherwise falls back to `timeMin`/`timeMax`. The response
    /// carries the calendar's `defaultReminders` inline (RN-04).
    func listEvents(timeMin: Date, timeMax: Date, syncToken: String?) async throws -> (events: [GoogleEvent], nextSyncToken: String?, defaultReminders: [GoogleCalendarDefaultReminder]?)
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

    func listEvents(timeMin: Date, timeMax: Date, syncToken: String?) async throws -> (events: [GoogleEvent], nextSyncToken: String?, defaultReminders: [GoogleCalendarDefaultReminder]?) {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("calendars/primary/events"),
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
            throw GoogleCalendarAPIError.unexpectedStatus(response.statusCode)
        }
        return data
    }
}
