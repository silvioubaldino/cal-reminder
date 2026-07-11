import AppKit
import Foundation
import Network

/// Obtains the OAuth authorization `code` from Google. Abstracted so `AuthManager`'s
/// token-exchange logic can be tested without a real browser + loopback server.
protocol AuthorizationCodeProviding {
    /// Starts a loopback listener, builds the authorization URL for the assigned
    /// `redirectURI`, opens it in the system browser, and waits for the redirect
    /// carrying `code`. Returns the code together with the exact `redirectURI` used
    /// (the token exchange must send back the same value).
    func requestAuthorizationCode(
        buildAuthorizationURL: @escaping (_ redirectURI: String) -> URL
    ) async throws -> (code: String, redirectURI: String)
}

/// Real implementation: a one-shot HTTP server on `127.0.0.1:<ephemeral port>` that
/// captures Google's OAuth redirect (Desktop-app loopback flow, RFC 8252).
final class LoopbackAuthorizationCodeProvider: AuthorizationCodeProviding {
    struct ProviderError: Error, CustomStringConvertible {
        let description: String
    }

    func requestAuthorizationCode(
        buildAuthorizationURL: @escaping (_ redirectURI: String) -> URL
    ) async throws -> (code: String, redirectURI: String) {
        let listener = try NWListener(using: .tcp, on: .any)

        // The listener must be started exactly once, with `newConnectionHandler` already
        // set (otherwise Google's redirect connection is dropped). We can't know the
        // ephemeral port until `.ready`, so the browser is opened from the state handler
        // once the port — and thus the redirectURI — is known.
        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            var redirectURI = ""

            func finish(_ result: Result<(code: String, redirectURI: String), Error>) {
                guard !resumed else { return }
                resumed = true
                listener.cancel()
                continuation.resume(with: result)
            }

            listener.newConnectionHandler = { connection in
                connection.start(queue: .main)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
                    if let error {
                        connection.cancel()
                        finish(.failure(error))
                        return
                    }
                    guard let data, let request = String(data: data, encoding: .utf8),
                          let code = Self.extractCode(from: request) else {
                        connection.cancel()
                        finish(.failure(ProviderError(description: "No authorization code in callback")))
                        return
                    }
                    connection.send(content: Self.htmlResponse(), completion: .contentProcessed { _ in
                        connection.cancel()
                        finish(.success((code: code, redirectURI: redirectURI)))
                    })
                }
            }

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let port = listener.port?.rawValue else {
                        finish(.failure(ProviderError(description: "Loopback listener has no assigned port")))
                        return
                    }
                    redirectURI = "http://127.0.0.1:\(port)/"
                    let url = buildAuthorizationURL(redirectURI)
                    DispatchQueue.main.async {
                        NSWorkspace.shared.open(url)
                    }
                case .failed(let error):
                    finish(.failure(error))
                default:
                    break
                }
            }

            listener.start(queue: .main)
        }
    }

    private static func extractCode(from rawRequest: String) -> String? {
        guard let requestLine = rawRequest.split(separator: "\r\n").first,
              let pathRange = requestLine.range(of: "GET ") else { return nil }
        let pathAndQuery = requestLine[pathRange.upperBound...]
            .split(separator: " ", maxSplits: 1)
            .first.map(String.init) ?? ""
        guard let queryStart = pathAndQuery.firstIndex(of: "?") else { return nil }
        let query = pathAndQuery[pathAndQuery.index(after: queryStart)...]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0] == "code" {
                return String(parts[1]).removingPercentEncoding
            }
        }
        return nil
    }

    private static func htmlResponse() -> Data {
        let body = "<html><body>cal-reminder is connected. You can close this tab.</body></html>"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        return Data(response.utf8)
    }
}
