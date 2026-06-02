import Foundation

/// Builds the appropriate `RequestAuthorizer` for a service from its stored
/// `Credential`, based on the service's `authenticationKind`.
///
/// Phase 1 services (header API keys) are fully wired here. Stateful schemes
/// (cookie/session logins for qBittorrent, Deluge, Transmission) are added by
/// their own service kits in later phases and slot in via the same protocol.
public enum AuthorizerFactory {
    public static func make(for type: ServiceType, credential: Credential) -> RequestAuthorizer {
        switch type.authenticationKind {
        case let .apiKeyHeader(headerName):
            return APIKeyHeaderAuthorizer(headerName: headerName, apiKey: credential.apiKeyValue ?? "")

        case let .apiKeyQuery(parameterName):
            return APIKeyQueryAuthorizer(parameterName: parameterName, apiKey: credential.apiKeyValue ?? "")

        case .basicAuth:
            if case let .usernamePassword(username, password) = credential {
                return BasicAuthorizer(username: username, password: password)
            }
            return NoAuthorizer()

        case .cookieSession, .transmissionSession, .sshCredentials:
            // Provided by the dedicated service kit in a later phase.
            return NoAuthorizer()
        }
    }
}
