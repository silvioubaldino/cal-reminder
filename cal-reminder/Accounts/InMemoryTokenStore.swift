import Foundation

final class InMemoryTokenStore: TokenStoring {
    private var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func refreshToken() -> String? { token }
    func setRefreshToken(_ token: String?) { self.token = token }
}
