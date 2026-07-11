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
        buildAuthorizationURL: (_ redirectURI: String) -> URL
    ) async throws -> (code: String, redirectURI: String)
}

/// Real implementation: a one-shot HTTP server on `127.0.0.1:<ephemeral port>` that
/// captures Google's OAuth redirect (Desktop-app loopback flow, RFC 8252).
final class LoopbackAuthorizationCodeProvider: AuthorizationCodeProviding {
    struct ProviderError: Error, CustomStringConvertible {
        let description: String
    }

    func requestAuthorizationCode(
        buildAuthorizationURL: (_ redirectURI: String) -> URL
    ) async throws -> (code: String, redirectURI: String) {
        let listener = try NWListener(using: .tcp, on: .any)

        let port = try await Self.waitForReadyPort(listener)
        let redirectURI = "http://127.0.0.1:\(port)/"
        let url = buildAuthorizationURL(redirectURI)

        await MainActor.run {
            NSWorkspace.shared.open(url)
        }

        let code = try await Self.waitForAuthorizationCode(listener)
        return (code, redirectURI)
    }

    private static func waitForReadyPort(_ listener: NWListener) async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    guard let port = listener.port?.rawValue else {
                        resumed = true
                        continuation.resume(throwing: ProviderError(description: "Loopback listener has no assigned port"))
                        return
                    }
                    resumed = true
                    continuation.resume(returning: port)
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: .main)
        }
    }

    private static func waitForAuthorizationCode(_ listener: NWListener) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            listener.newConnectionHandler = { connection in
                connection.start(queue: .main)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
                    defer {
                        connection.cancel()
                        listener.cancel()
                    }
                    guard !resumed else { return }
                    if let error {
                        resumed = true
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let data, let request = String(data: data, encoding: .utf8),
                          let code = extractCode(from: request) else {
                        resumed = true
                        continuation.resume(throwing: ProviderError(description: "No authorization code in callback"))
                        return
                    }
                    connection.send(content: htmlResponse(), completion: .contentProcessed { _ in
                        resumed = true
                        continuation.resume(returning: code)
                    })
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
