import Foundation

enum AccountProvider: String, Codable {
    case google
}

struct Account: Identifiable, Equatable, Codable {
    let id: String
    let provider: AccountProvider
    let label: String

    static func id(provider: AccountProvider, providerUserId: String) -> String {
        "\(provider.rawValue):\(providerUserId)"
    }
}
