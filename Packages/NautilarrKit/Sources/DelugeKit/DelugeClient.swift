import Foundation
import NautilarrCore

// MARK: - Authorizer

/// Cookie-session authorizer for Deluge's Web JSON-RPC. Logs in with the Web UI
/// password via `auth.login`, which sets a session cookie stored by the shared
/// `URLSession`. Deluge signals a bad login with `{"result": false}` and HTTP
/// 200 (not 401), so the result body is inspected.
public final class DelugeAuthorizer: RequestAuthorizer, @unchecked Sendable {
    private let baseURL: URL?
    private let password: String
    private let lock = NSLock()
    private var loggedIn = false

    public init(baseURL: URL?, password: String) {
        self.baseURL = baseURL
        self.password = password
    }

    private var isLoggedIn: Bool { lock.lock(); defer { lock.unlock() }; return loggedIn }
    private func setLoggedIn(_ v: Bool) { lock.lock(); defer { lock.unlock() }; loggedIn = v }

    public func authorize(_ request: inout URLRequest, using session: URLSession) async throws {
        if !isLoggedIn { try await login(using: session) }
    }

    public func handleAuthenticationFailure(using session: URLSession) async -> Bool {
        setLoggedIn(false)
        do { try await login(using: session); return true } catch { return false }
    }

    private func login(using session: URLSession) async throws {
        guard let baseURL else { throw APIError.invalidBaseURL }
        var request = URLRequest(url: baseURL.appendingPathComponent("json"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["method": "auth.login", "params": [password], "id": 1])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw APIError.unauthorized }
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let ok = object?["result"] as? Bool, ok { setLoggedIn(true) } else { throw APIError.unauthorized }
    }
}

// MARK: - Models

/// A torrent from `core.get_torrents_status`.
public struct DelugeTorrent: Codable, Sendable, Equatable, Hashable, Identifiable {
    /// Info-hash, injected from the result dictionary key.
    public var id: String = ""
    public var name: String?
    /// Deluge reports progress as a percentage (`0...100`).
    public var progress: Double?
    /// `Downloading`, `Seeding`, `Paused`, `Queued`, `Checking`, `Error`.
    public var state: String?
    public var downloadPayloadRate: Int?
    public var uploadPayloadRate: Int?
    public var totalSize: Int64?
    public var eta: Int?
    /// Seconds spent seeding (`seeding_time`). Used for the seed-time limit.
    public var seedingTime: Int?
    public var ratio: Double?

    private enum CodingKeys: String, CodingKey {
        case name, progress, state, eta, ratio
        case downloadPayloadRate = "download_payload_rate"
        case uploadPayloadRate = "upload_payload_rate"
        case totalSize = "total_size"
        case seedingTime = "seeding_time"
    }

    public var fractionDone: Double { (progress ?? 0) / 100 }
    public var isPaused: Bool { state?.lowercased() == "paused" }
    public var hasError: Bool { state?.lowercased() == "error" }
    public var isSeeding: Bool { state?.lowercased() == "seeding" }
}

private struct DelugeRPCError: Decodable, Sendable { let message: String? }
private struct DelugeEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    let result: T?
    let error: DelugeRPCError?
}

// MARK: - Client

/// Client for the Deluge Web JSON-RPC API (`/json`). Builds its own `APIClient`
/// with a `DelugeAuthorizer` (password login → session cookie).
///
/// API reference (public, official):
/// https://deluge.readthedocs.io/en/latest/reference/api.html
public struct DelugeClient: Sendable {
    private let api: APIClient
    private static let fields = ["name", "progress", "state", "download_payload_rate",
                                 "upload_payload_rate", "total_size", "eta",
                                 "seeding_time", "ratio"]

    public init(api: APIClient) { self.api = api }

    public init(instance: ServiceInstance, credential: Credential) {
        let urls = instance.candidateBaseURLs()
        let hosts = Set(urls.compactMap { $0.host })
        var password = ""
        if case let .usernamePassword(_, p) = credential { password = p }
        if case let .apiKey(key) = credential { password = key }
        self.api = APIClient(
            baseURLProvider: { urls },
            authorizer: DelugeAuthorizer(baseURL: urls.first, password: password),
            extraHeaders: instance.customHeaders,
            allowSelfSignedHosts: instance.allowSelfSignedCertificates ? hosts : [],
            timeout: instance.timeout
        )
    }

    private func call<T: Decodable & Sendable>(_ method: String, params: [Any], as type: T.Type) async throws -> T {
        let endpoint = try Endpoint.jsonObject("json", object: ["method": method, "params": params, "id": 1])
        let envelope: DelugeEnvelope<T> = try await api.send(endpoint)
        if let message = envelope.error?.message { throw APIError.server(statusCode: 200, body: message) }
        guard let value = envelope.result else { throw APIError.invalidResponse }
        return value
    }

    private func callVoid(_ method: String, params: [Any]) async throws {
        let endpoint = try Endpoint.jsonObject("json", object: ["method": method, "params": params, "id": 1])
        struct VoidEnvelope: Decodable { let error: DelugeRPCError? }
        let envelope: VoidEnvelope = try await api.send(endpoint)
        if let message = envelope.error?.message { throw APIError.server(statusCode: 200, body: message) }
    }

    // MARK: Connection test
    // VERIFY: `daemon.get_version` returns the daemon version on a connected
    // Web UI; adjust if the deployed Deluge exposes it differently.
    public func version() async throws -> String { try await call("daemon.get_version", params: [], as: String.self) }

    // MARK: Torrents
    public func torrents() async throws -> [DelugeTorrent] {
        // core.get_torrents_status(filter_dict, keys) → { hash: { fields } }
        let dict = try await call("core.get_torrents_status", params: [[String: String](), Self.fields], as: [String: DelugeTorrent].self)
        return dict.map { hash, torrent in
            var t = torrent; t.id = hash; return t
        }.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    public func pause(hashes: [String]) async throws { try await callVoid("core.pause_torrent", params: [hashes]) }
    public func resume(hashes: [String]) async throws { try await callVoid("core.resume_torrent", params: [hashes]) }
    public func remove(hash: String, removeData: Bool) async throws {
        try await callVoid("core.remove_torrent", params: [hash, removeData])
    }

    /// Adds a torrent from a magnet URI.
    // VERIFY: core.add_torrent_magnet(uri, options).
    public func addMagnet(_ url: String) async throws {
        try await callVoid("core.add_torrent_magnet", params: [url, [String: String]()])
    }

    /// Forces a re-check of the given torrents.
    // VERIFY: core.force_recheck(torrent_ids).
    public func forceRecheck(hashes: [String]) async throws {
        try await callVoid("core.force_recheck", params: [hashes])
    }
}
