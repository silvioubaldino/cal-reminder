import Foundation

/// The provider a connected Account belongs to (GLO: Account). Only `.google` exists today;
/// kept explicit (rather than assumed) so a future non-Google source can be added without
/// re-keying every stored Account, Keychain entry, or Calendar selection (AYD-007).
enum AccountProvider: String, Codable {
    case google
}

/// A connected Account (GLO): an OAuth session that owns a set of Calendars. `id` is
/// namespaced per provider so ids from different sources can never collide (AYD-007, TDR-005).
struct Account: Identifiable, Equatable, Codable {
    let id: String
    let provider: AccountProvider
    /// Display label shown in the menu (RF-06) — the account's email. Not part of `id`:
    /// an email can change (Workspace rename, alias) without the Account losing its identity.
    let label: String

    /// Builds the namespaced id from the provider's own immutable user id (e.g. Google's `sub`).
    static func id(provider: AccountProvider, providerUserId: String) -> String {
        "\(provider.rawValue):\(providerUserId)"
    }
}
