import Foundation

/// A generic async/await HTTP client used by every service integration.
///
/// Responsibilities:
/// - Resolve an ordered list of candidate base URLs (LAN/WAN failover).
/// - Apply per-instance custom headers and an authentication strategy.
/// - Optionally trust self-signed certificates for the instance's hosts only.
/// - Normalise transport and HTTP errors into `APIError`.
///
/// One `APIClient` is created per `ServiceInstance`. Service-specific clients
/// (e.g. `SonarrClient`) wrap an `APIClient` and expose typed methods.
public final class APIClient: @unchecked Sendable {
    /// Returns the ordered base URLs to attempt. Re-evaluated per request so it
    /// can reflect the current network (LAN first vs. WAN first).
    public typealias BaseURLProvider = @Sendable () -> [URL]

    /// Per-request timeout for endpoints that block server-side while the *arr
    /// queries every configured indexer (interactive release search). The normal
    /// 30 s default times these out before the search returns, which surfaces as
    /// "No releases found"; opt those endpoints into this longer budget instead.
    public static let interactiveSearchTimeout: TimeInterval = 120

    private let baseURLProvider: BaseURLProvider
    private let authorizer: RequestAuthorizer
    private let extraHeaders: [String: String]
    private let session: URLSession
    private let decoder: JSONDecoder
    private let timeout: TimeInterval

    /// - Parameters:
    ///   - baseURLProvider: ordered candidate base URLs (failover order).
    ///   - authorizer: authentication strategy.
    ///   - extraHeaders: per-instance custom headers (e.g. Cloudflare Access).
    ///   - allowSelfSignedHosts: hosts for which TLS validation is relaxed.
    ///   - timeout: per-request timeout, seconds.
    ///   - decoder: JSON decoder (defaults to the lenient `.nautilarr`).
    ///   - sessionConfiguration: optional override (used by tests to inject a
    ///     mock `URLProtocol`).
    public init(
        baseURLProvider: @escaping BaseURLProvider,
        authorizer: RequestAuthorizer = NoAuthorizer(),
        extraHeaders: [String: String] = [:],
        allowSelfSignedHosts: Set<String> = [],
        timeout: TimeInterval = 30,
        decoder: JSONDecoder = .nautilarr,
        sessionConfiguration: URLSessionConfiguration? = nil
    ) {
        self.baseURLProvider = baseURLProvider
        self.authorizer = authorizer
        self.extraHeaders = extraHeaders
        self.timeout = timeout
        self.decoder = decoder

        let configuration = sessionConfiguration ?? .ephemeral
        // The session ceiling must allow the longest per-request timeout an
        // endpoint may opt into (interactive search), or it would cap those
        // requests early. Ordinary requests still bound themselves with their own
        // (shorter) `URLRequest.timeoutInterval`, set per request in `makeRequest`.
        configuration.timeoutIntervalForRequest = max(timeout, Self.interactiveSearchTimeout)
        configuration.waitsForConnectivity = false

        if allowSelfSignedHosts.isEmpty {
            self.session = URLSession(configuration: configuration)
        } else {
            let delegate = SelfSignedTrustDelegate(allowedHosts: allowSelfSignedHosts)
            self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        }
    }

    // MARK: - Convenience initialiser from a ServiceInstance

    /// Builds a client for an instance using a static (non network-aware) host
    /// order. Network-aware ordering is layered on by `HostResolver`.
    public convenience init(
        instance: ServiceInstance,
        authorizer: RequestAuthorizer,
        preferFallbackFirst: Bool = false,
        sessionConfiguration: URLSessionConfiguration? = nil
    ) {
        let urls = instance.candidateBaseURLs(preferFallbackFirst: preferFallbackFirst)
        let hosts = Set(urls.compactMap { $0.host })
        self.init(
            baseURLProvider: { urls },
            authorizer: authorizer,
            extraHeaders: instance.customHeaders,
            allowSelfSignedHosts: instance.allowSelfSignedCertificates ? hosts : [],
            timeout: instance.timeout,
            sessionConfiguration: sessionConfiguration
        )
    }

    // MARK: - Sending

    /// Sends a request and decodes the JSON response into `Response`.
    public func send<Response: Decodable>(_ endpoint: Endpoint, as type: Response.Type = Response.self) async throws -> Response {
        let data = try await sendReturningData(endpoint)
        if data.isEmpty, let empty = EmptyResponse() as? Response {
            return empty
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Sends a request, ignoring the response body (e.g. `DELETE`).
    @discardableResult
    public func send(_ endpoint: Endpoint) async throws -> Data {
        try await sendReturningData(endpoint)
    }

    /// Core send loop with host failover. Tries each candidate base URL in turn
    /// and returns the first success. Any failure on one host advances to the
    /// next candidate — not just transport errors, because an off-LAN device may
    /// answer the primary host's address with an unexpected HTTP/redirect/HTML
    /// response (404, 5xx, decoding error, …) that should still fall back to the
    /// WAN/reverse-proxy host. Cancellation propagates immediately. When every
    /// host fails, the most actionable error is surfaced.
    public func sendReturningData(_ endpoint: Endpoint) async throws -> Data {
        let candidates = baseURLProvider()
        guard !candidates.isEmpty else { throw APIError.invalidBaseURL }

        var failures: [(host: String, error: APIError)] = []

        for baseURL in candidates {
            try Task.checkCancellation()
            do {
                return try await perform(endpoint, baseURL: baseURL, allowAuthRetry: true)
            } catch let error as APIError {
                if case .cancelled = error { throw error }
                failures.append((baseURL.host ?? baseURL.absoluteString, error))
                continue
            }
        }

        throw Self.mostActionableError(from: failures)
    }

    /// Chooses the clearest error to surface after every host failed. An error
    /// that proves a real service answered (auth/HTTP) is more useful than a
    /// generic "couldn't connect", so it wins; if only transport errors
    /// occurred, they're reported together.
    private static func mostActionableError(from failures: [(host: String, error: APIError)]) -> APIError {
        guard !failures.isEmpty else { return .invalidBaseURL }
        if failures.count == 1 { return failures[0].error }

        func priority(_ error: APIError) -> Int {
            switch error {
            case .unauthorized: return 6
            case .forbidden: return 5
            case .notFound: return 4
            case .server: return 3
            case .decoding: return 2
            case .timedOut: return 1
            default: return 0   // transport / invalidBaseURL / others
            }
        }
        if let best = failures.map(\.error).max(by: { priority($0) < priority($1) }), priority(best) > 0 {
            return best
        }
        return .allHostsFailed(failures.map { "\($0.host): \($0.error.localizedDescription)" })
    }

    private func perform(_ endpoint: Endpoint, baseURL: URL, allowAuthRetry: Bool) async throws -> Data {
        var request = try makeRequest(endpoint, baseURL: baseURL)
        try await authorizer.authorize(&request, using: session)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.from(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            return data
        case 401, 403:
            // Give a stateful authorizer one chance to refresh and retry.
            if allowAuthRetry, await authorizer.handleAuthenticationFailure(using: session) {
                return try await perform(endpoint, baseURL: baseURL, allowAuthRetry: false)
            }
            throw http.statusCode == 401 ? APIError.unauthorized : APIError.forbidden
        case 404:
            throw APIError.notFound
        case 409:
            // CSRF / session-id challenge (Transmission): let the authorizer
            // capture the challenge header and retry once.
            if allowAuthRetry, await authorizer.update(fromChallengeResponse: http, using: session) {
                return try await perform(endpoint, baseURL: baseURL, allowAuthRetry: false)
            }
            let snippet = String(data: data.prefix(512), encoding: .utf8)
            throw APIError.server(statusCode: 409, body: snippet)
        default:
            let snippet = String(data: data.prefix(512), encoding: .utf8)
            throw APIError.server(statusCode: http.statusCode, body: snippet)
        }
    }

    private func makeRequest(_ endpoint: Endpoint, baseURL: URL) throws -> URLRequest {
        // Append the endpoint path to the base URL's existing path.
        let trimmedPath = endpoint.path.hasPrefix("/") ? String(endpoint.path.dropFirst()) : endpoint.path
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidBaseURL
        }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + "/" + trimmedPath
        if !endpoint.queryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + endpoint.queryItems
        }
        guard let url = components.url else { throw APIError.invalidBaseURL }

        var request = URLRequest(url: url, timeoutInterval: endpoint.timeout ?? timeout)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Per-instance custom headers first, then endpoint-specific headers
        // (endpoint wins on conflict).
        for (key, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: key) }
        for (key, value) in endpoint.additionalHeaders { request.setValue(value, forHTTPHeaderField: key) }

        return request
    }
}

/// Sentinel allowing `send(as:)` to succeed on an empty body when the caller
/// expects `EmptyResponse`.
public struct EmptyResponse: Decodable, Sendable {
    public init() {}
}
