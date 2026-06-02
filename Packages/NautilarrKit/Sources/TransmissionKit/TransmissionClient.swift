import Foundation
import NautilarrCore

// MARK: - Authorizer

/// Authorizer for Transmission's RPC. Transmission protects against CSRF by
/// requiring an `X-Transmission-Session-Id` header: the first request returns
/// `409` with the id in the response header, which must be echoed on the retry.
/// Optional HTTP Basic credentials are attached when configured.
public final class TransmissionAuthorizer: RequestAuthorizer, @unchecked Sendable {
    private let username: String?
    private let password: String?
    private let lock = NSLock()
    private var sessionId: String?

    public init(username: String?, password: String?) {
        self.username = username
        self.password = password
    }

    private func currentSessionId() -> String? { lock.lock(); defer { lock.unlock() }; return sessionId }
    private func setSessionId(_ id: String) { lock.lock(); defer { lock.unlock() }; sessionId = id }

    public func authorize(_ request: inout URLRequest, using session: URLSession) async throws {
        if let username, !username.isEmpty {
            let token = Data("\(username):\(password ?? "")".utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }
        if let id = currentSessionId() { request.setValue(id, forHTTPHeaderField: "X-Transmission-Session-Id") }
    }

    public func update(fromChallengeResponse response: HTTPURLResponse, using session: URLSession) async -> Bool {
        // Header lookup is case-insensitive on HTTPURLResponse.
        guard let id = response.value(forHTTPHeaderField: "X-Transmission-Session-Id") else { return false }
        setSessionId(id)
        return true
    }
}

// MARK: - Models

/// A torrent from `torrent-get`.
public struct TransmissionTorrent: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var name: String?
    /// 0 stopped · 1 check-wait · 2 checking · 3 download-wait · 4 downloading ·
    /// 5 seed-wait · 6 seeding.
    public var status: Int?
    public var percentDone: Double?
    public var rateDownload: Int?
    public var rateUpload: Int?
    public var totalSize: Int64?
    public var eta: Int?
    public var errorString: String?
    /// Seconds spent seeding (`secondsSeeding`). Used for the seed-time limit.
    public var secondsSeeding: Int?
    public var uploadRatio: Double?

    public var progress: Double { percentDone ?? 0 }
    public var isSeeding: Bool { status == 5 || status == 6 }
    public var isPaused: Bool { status == 0 }
    public var hasError: Bool { !(errorString ?? "").isEmpty }
    public var displayState: String {
        switch status {
        case 0: return "Stopped"
        case 1, 2: return "Checking"
        case 3: return "Queued"
        case 4: return "Downloading"
        case 5: return "Queued (seed)"
        case 6: return "Seeding"
        default: return "Unknown"
        }
    }
}

private struct TorrentsArguments: Decodable, Sendable { let torrents: [TransmissionTorrent] }
private struct SessionArguments: Decodable, Sendable { let version: String? }
private struct Envelope<T: Decodable & Sendable>: Decodable, Sendable {
    let result: String
    let arguments: T?
}

// MARK: - Client

/// Client for the Transmission RPC API. Builds its own `APIClient` with a
/// `TransmissionAuthorizer` (session-id challenge handled via `APIClient`'s 409
/// retry hook).
///
/// API reference (public, official):
/// https://github.com/transmission/transmission/blob/main/docs/rpc-spec.md
public struct TransmissionClient: Sendable {
    private let api: APIClient
    private static let path = "transmission/rpc"
    private static let fields = ["id", "name", "status", "percentDone", "rateDownload",
                                 "rateUpload", "totalSize", "eta", "errorString",
                                 "secondsSeeding", "uploadRatio"]

    public init(api: APIClient) { self.api = api }

    public init(instance: ServiceInstance, credential: Credential) {
        let urls = instance.candidateBaseURLs()
        let hosts = Set(urls.compactMap { $0.host })
        var username: String?
        var password: String?
        if case let .usernamePassword(u, p) = credential { username = u; password = p }
        self.api = APIClient(
            baseURLProvider: { urls },
            authorizer: TransmissionAuthorizer(username: username, password: password),
            extraHeaders: instance.customHeaders,
            allowSelfSignedHosts: instance.allowSelfSignedCertificates ? hosts : [],
            timeout: instance.timeout
        )
    }

    private func rpc<T: Decodable & Sendable>(_ method: String, arguments: [String: Any], as type: T.Type) async throws -> T {
        let endpoint = try Endpoint.jsonObject(Self.path, object: ["method": method, "arguments": arguments])
        let envelope: Envelope<T> = try await api.send(endpoint)
        guard envelope.result == "success", let value = envelope.arguments else {
            throw APIError.server(statusCode: 200, body: envelope.result)
        }
        return value
    }

    private func action(_ method: String, arguments: [String: Any]) async throws {
        let endpoint = try Endpoint.jsonObject(Self.path, object: ["method": method, "arguments": arguments])
        struct ResultOnly: Decodable { let result: String }
        let result: ResultOnly = try await api.send(endpoint)
        guard result.result == "success" else { throw APIError.server(statusCode: 200, body: result.result) }
    }

    // MARK: Connection test
    public func version() async throws -> String {
        let args = try await rpc("session-get", arguments: [:], as: SessionArguments.self)
        return args.version ?? "unknown"
    }

    // MARK: Torrents
    public func torrents() async throws -> [TransmissionTorrent] {
        try await rpc("torrent-get", arguments: ["fields": Self.fields], as: TorrentsArguments.self).torrents
    }
    public func start(ids: [Int]) async throws { try await action("torrent-start", arguments: ["ids": ids]) }
    public func stop(ids: [Int]) async throws { try await action("torrent-stop", arguments: ["ids": ids]) }
    public func remove(ids: [Int], deleteData: Bool) async throws {
        try await action("torrent-remove", arguments: ["ids": ids, "delete-local-data": deleteData])
    }

    /// Adds a torrent from a magnet link or .torrent URL.
    // VERIFY: torrent-add with `filename` set to a magnet/URL.
    public func addMagnet(_ url: String) async throws {
        try await action("torrent-add", arguments: ["filename": url])
    }

    /// Forces a re-verify (re-check) of the given torrents.
    public func verify(ids: [Int]) async throws {
        try await action("torrent-verify", arguments: ["ids": ids])
    }
}
