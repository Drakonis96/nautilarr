import Foundation

/// A secret used to authenticate with a service. Persisted **only** in the
/// Keychain (see `CredentialStore`), never in plain `UserDefaults` or alongside
/// the `ServiceInstance`.
public enum Credential: Codable, Equatable, Sendable {
    /// API key / token (Sonarr, Radarr, Overseerr, SABnzbd, Tautulli, …).
    case apiKey(String)
    /// Username + password (NZBGet basic auth, qBittorrent, Deluge web UI).
    case usernamePassword(username: String, password: String)
    /// SSH credentials. `privateKey` is PEM/OpenSSH text when key-based auth is
    /// used; `password` is used for password auth or as the key passphrase.
    case ssh(username: String, password: String?, privateKey: String?)
    /// No authentication required.
    case none

    /// Convenience accessor for the single-secret case.
    public var apiKeyValue: String? {
        if case let .apiKey(key) = self { return key }
        return nil
    }

    public var isEmpty: Bool {
        switch self {
        case .none:
            return true
        case let .apiKey(key):
            return key.isEmpty
        case let .usernamePassword(username, password):
            return username.isEmpty && password.isEmpty
        case let .ssh(username, password, privateKey):
            return username.isEmpty && (password?.isEmpty ?? true) && (privateKey?.isEmpty ?? true)
        }
    }
}
