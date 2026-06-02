import Foundation

/// Attaches authentication to outgoing requests. Implementations may be
/// stateless (header/query injection) or stateful (cookie/session login),
/// hence the `async` interface — a cookie-based authorizer can perform a login
/// round-trip and cache the result.
public protocol RequestAuthorizer: Sendable {
    /// Mutates the request to carry authentication. `session` is provided so
    /// stateful authorizers can perform a login if needed.
    func authorize(_ request: inout URLRequest, using session: URLSession) async throws

    /// Called by `APIClient` when a request comes back `401`/`403`, so a
    /// stateful authorizer can invalidate a cached session before one retry.
    /// Returns `true` if it refreshed and a retry is worthwhile.
    func handleAuthenticationFailure(using session: URLSession) async -> Bool

    /// Called by `APIClient` on a `409 Conflict`, used by Transmission's CSRF
    /// session-id challenge: the response carries `X-Transmission-Session-Id`,
    /// which must be echoed on the retry. Read what's needed from `response`,
    /// update internal state and return `true` to request a single retry.
    func update(fromChallengeResponse response: HTTPURLResponse, using session: URLSession) async -> Bool
}

public extension RequestAuthorizer {
    func handleAuthenticationFailure(using session: URLSession) async -> Bool { false }
    func update(fromChallengeResponse response: HTTPURLResponse, using session: URLSession) async -> Bool { false }
}

/// No-op authorizer for services that need no authentication.
public struct NoAuthorizer: RequestAuthorizer {
    public init() {}
    public func authorize(_ request: inout URLRequest, using session: URLSession) async throws {}
}

/// Injects an API key into a request header (e.g. `X-Api-Key`).
public struct APIKeyHeaderAuthorizer: RequestAuthorizer {
    public let headerName: String
    public let apiKey: String

    public init(headerName: String, apiKey: String) {
        self.headerName = headerName
        self.apiKey = apiKey
    }

    public func authorize(_ request: inout URLRequest, using session: URLSession) async throws {
        request.setValue(apiKey, forHTTPHeaderField: headerName)
    }
}

/// Appends an API key as a query parameter (e.g. `?apikey=…`), used by services
/// like SABnzbd and Tautulli.
public struct APIKeyQueryAuthorizer: RequestAuthorizer {
    public let parameterName: String
    public let apiKey: String

    public init(parameterName: String, apiKey: String) {
        self.parameterName = parameterName
        self.apiKey = apiKey
    }

    public func authorize(_ request: inout URLRequest, using session: URLSession) async throws {
        guard let url = request.url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == parameterName }
        items.append(URLQueryItem(name: parameterName, value: apiKey))
        components.queryItems = items
        request.url = components.url
    }
}

/// HTTP Basic authentication (e.g. NZBGet, or a reverse proxy).
public struct BasicAuthorizer: RequestAuthorizer {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    public func authorize(_ request: inout URLRequest, using session: URLSession) async throws {
        let pair = "\(username):\(password)"
        let token = Data(pair.utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
    }
}
