import Foundation
import NautilarrCore

// MARK: - Lenient decoding helpers

/// Tautulli's API returns numbers as either JSON numbers or quoted strings
/// depending on the field and version, so we decode tolerantly.
private extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return String(d) }
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return String(b) }
        return nil
    }
    func lenientInt(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int(s) }
        return nil
    }
}

// MARK: - Models

/// A single playback session from `get_activity`.
public struct TautulliSession: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { sessionKey ?? UUID().uuidString }
    public var sessionKey: String?
    public var user: String?
    public var fullTitle: String?
    public var title: String?
    public var grandparentTitle: String?
    /// `playing`, `paused`, `buffering`.
    public var state: String?
    public var mediaType: String?
    public var player: String?
    public var progressPercent: String?
    public var transcodeDecision: String?
    public var qualityProfile: String?

    public init(sessionKey: String? = nil, user: String? = nil, fullTitle: String? = nil,
                title: String? = nil, grandparentTitle: String? = nil, state: String? = nil,
                mediaType: String? = nil, player: String? = nil, progressPercent: String? = nil,
                transcodeDecision: String? = nil, qualityProfile: String? = nil) {
        self.sessionKey = sessionKey; self.user = user; self.fullTitle = fullTitle
        self.title = title; self.grandparentTitle = grandparentTitle; self.state = state
        self.mediaType = mediaType; self.player = player; self.progressPercent = progressPercent
        self.transcodeDecision = transcodeDecision; self.qualityProfile = qualityProfile
    }

    private enum CodingKeys: String, CodingKey {
        case sessionKey = "session_key"
        case user, title, state, player
        case fullTitle = "full_title"
        case grandparentTitle = "grandparent_title"
        case mediaType = "media_type"
        case progressPercent = "progress_percent"
        case transcodeDecision = "transcode_decision"
        case qualityProfile = "quality_profile"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionKey = c.lenientString(.sessionKey)
        user = c.lenientString(.user)
        title = c.lenientString(.title)
        state = c.lenientString(.state)
        player = c.lenientString(.player)
        fullTitle = c.lenientString(.fullTitle)
        grandparentTitle = c.lenientString(.grandparentTitle)
        mediaType = c.lenientString(.mediaType)
        progressPercent = c.lenientString(.progressPercent)
        transcodeDecision = c.lenientString(.transcodeDecision)
        qualityProfile = c.lenientString(.qualityProfile)
    }

    public var progress: Double {
        guard let p = progressPercent, let value = Double(p) else { return 0 }
        return max(0, min(1, value / 100))
    }
    public var displayTitle: String { fullTitle ?? grandparentTitle ?? title ?? "Unknown" }
    public var isTranscoding: Bool { transcodeDecision?.lowercased() == "transcode" }
}

/// `get_activity` data payload.
public struct TautulliActivity: Codable, Sendable, Equatable {
    public var streamCount: String?
    public var totalBandwidth: Int?
    public var sessions: [TautulliSession]

    public init(streamCount: String? = nil, totalBandwidth: Int? = nil, sessions: [TautulliSession] = []) {
        self.streamCount = streamCount; self.totalBandwidth = totalBandwidth; self.sessions = sessions
    }

    private enum CodingKeys: String, CodingKey {
        case streamCount = "stream_count"
        case totalBandwidth = "total_bandwidth"
        case sessions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streamCount = c.lenientString(.streamCount)
        totalBandwidth = c.lenientInt(.totalBandwidth)
        // A missing/odd sessions array shouldn't blank the whole activity.
        sessions = (try? c.decode([TautulliSession].self, forKey: .sessions)) ?? []
    }

    public var count: Int { Int(streamCount ?? "") ?? sessions.count }
}

/// `get_server_info` data payload.
public struct TautulliServerInfo: Codable, Sendable, Equatable {
    public var pmsVersion: String?
    public var pmsName: String?
    private enum CodingKeys: String, CodingKey {
        case pmsVersion = "pms_version"
        case pmsName = "pms_name"
    }
}

/// Tautulli envelope: `{ "response": { "result": "success", "data": <T> } }`.
private struct TautulliEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    struct Response: Decodable, Sendable {
        let result: String?
        let message: String?
        let data: T?
    }
    let response: Response
}

/// A data-agnostic envelope used by the connection probe — it only inspects
/// `result`/`message`, never the (version-variable) `data` payload, so a valid
/// connection can't be reported as a failure just because of a decode mismatch.
private struct TautulliBareEnvelope: Decodable, Sendable {
    struct Response: Decodable, Sendable {
        let result: String?
        let message: String?
    }
    let response: Response
}

// MARK: - Client

/// Client for the Tautulli API (Plex monitoring). Uses the `?apikey=&cmd=`
/// query style; the key is attached by `APIKeyQueryAuthorizer` via
/// `ServiceClientFactory`.
///
/// API reference (public, official): https://github.com/Tautulli/Tautulli/wiki/Tautulli-API-Reference
/// Endpoint form: `http://host:8181[/HTTP_ROOT]/api/v2?apikey=…&cmd=…`.
public struct TautulliClient: Sendable {
    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public init(instance: ServiceInstance, credential: Credential, monitor: NetworkMonitor? = nil) {
        self.api = ServiceClientFactory.makeClient(for: instance, credential: credential, monitor: monitor)
    }

    private func call<T: Decodable & Sendable>(_ cmd: String, params: [URLQueryItem] = [], as type: T.Type = T.self) async throws -> T {
        var query = [URLQueryItem(name: "cmd", value: cmd)]
        query.append(contentsOf: params)
        let envelope: TautulliEnvelope<T> = try await api.send(.get("api/v2", query: query))
        guard envelope.response.result == "success", let data = envelope.response.data else {
            throw APIError.server(statusCode: 200, body: envelope.response.message ?? "Tautulli error")
        }
        return data
    }

    /// Lightweight connectivity probe used by the connection test. Validates the
    /// endpoint + API key without decoding the full activity payload (whose field
    /// types vary by Tautulli version). Uses `get_server_info`, which doesn't
    /// depend on Plex being reachable.
    public func ping() async throws {
        let bare: TautulliBareEnvelope = try await api.send(.get("api/v2", query: [
            URLQueryItem(name: "cmd", value: "get_server_info")
        ]))
        guard bare.response.result == "success" else {
            throw APIError.server(statusCode: 200, body: bare.response.message ?? "Tautulli rejected the request")
        }
    }

    /// Currently-playing streams.
    public func activity() async throws -> TautulliActivity {
        try await call("get_activity")
    }

    /// Server details (Plex Media Server name/version Tautulli is monitoring).
    public func serverInfo() async throws -> TautulliServerInfo {
        try await call("get_server_info")
    }
}
