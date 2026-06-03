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
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int(Double(s) ?? 0) }
        return nil
    }
    func lenientDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return Double(i) }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s) }
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

// MARK: - History

/// One row from `get_history`.
public struct TautulliHistoryRecord: Decodable, Sendable, Identifiable, Equatable, Hashable {
    public var rowId: Int?
    public var dateEpoch: Int?
    public var user: String?
    public var friendlyName: String?
    public var fullTitle: String?
    public var title: String?
    public var grandparentTitle: String?
    public var mediaType: String?
    public var player: String?
    public var transcodeDecision: String?
    public var percentComplete: Int?
    public var watchedStatus: Double?

    public var id: String { rowId.map(String.init) ?? "\(dateEpoch ?? 0)-\(title ?? "")-\(user ?? "")" }
    public var displayTitle: String { fullTitle ?? grandparentTitle ?? title ?? "Unknown" }
    public var date: Date? { dateEpoch.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    public var isTranscoding: Bool { transcodeDecision?.lowercased() == "transcode" }
    public var progress: Double { max(0, min(1, Double(percentComplete ?? 0) / 100)) }

    private enum CodingKeys: String, CodingKey {
        case rowId = "row_id"
        case dateEpoch = "date"
        case user
        case friendlyName = "friendly_name"
        case fullTitle = "full_title"
        case title
        case grandparentTitle = "grandparent_title"
        case mediaType = "media_type"
        case player
        case transcodeDecision = "transcode_decision"
        case percentComplete = "percent_complete"
        case watchedStatus = "watched_status"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rowId = c.lenientInt(.rowId)
        dateEpoch = c.lenientInt(.dateEpoch)
        user = c.lenientString(.user)
        friendlyName = c.lenientString(.friendlyName)
        fullTitle = c.lenientString(.fullTitle)
        title = c.lenientString(.title)
        grandparentTitle = c.lenientString(.grandparentTitle)
        mediaType = c.lenientString(.mediaType)
        player = c.lenientString(.player)
        transcodeDecision = c.lenientString(.transcodeDecision)
        percentComplete = c.lenientInt(.percentComplete)
        watchedStatus = c.lenientDouble(.watchedStatus)
    }
}

/// `get_history` data payload (`{ recordsTotal, data: [...] }`).
public struct TautulliHistory: Decodable, Sendable {
    public var recordsTotal: Int?
    public var data: [TautulliHistoryRecord]
    private enum CodingKeys: String, CodingKey { case recordsTotal, data }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recordsTotal = c.lenientInt(.recordsTotal)
        data = (try? c.decode([TautulliHistoryRecord].self, forKey: .data)) ?? []
    }
}

// MARK: - Home statistics

/// One row inside a `get_home_stats` group. Different stat groups populate
/// different fields, so this is decoded leniently and the UI picks what's present.
public struct TautulliStatRow: Decodable, Sendable, Identifiable, Equatable, Hashable {
    public var title: String?
    public var user: String?
    public var friendlyName: String?
    public var platform: String?
    public var totalPlays: Int?
    public var totalDuration: Int?
    public var ratingKey: String?

    public var id: String { "\(title ?? "")\(friendlyName ?? user ?? "")\(platform ?? "")\(ratingKey ?? "")" }
    /// The most relevant label for this row, whatever kind of stat it is.
    public var label: String { title ?? friendlyName ?? user ?? platform ?? "—" }

    private enum CodingKeys: String, CodingKey {
        case title, user, platform
        case friendlyName = "friendly_name"
        case totalPlays = "total_plays"
        case totalDuration = "total_duration"
        case ratingKey = "rating_key"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = c.lenientString(.title)
        user = c.lenientString(.user)
        friendlyName = c.lenientString(.friendlyName)
        platform = c.lenientString(.platform)
        totalPlays = c.lenientInt(.totalPlays)
        totalDuration = c.lenientInt(.totalDuration)
        ratingKey = c.lenientString(.ratingKey)
    }
}

/// One group from `get_home_stats` (e.g. "Most Watched Movies").
public struct TautulliHomeStat: Decodable, Sendable, Identifiable {
    public var statId: String?
    public var statTitle: String?
    public var rows: [TautulliStatRow]

    public var id: String { statId ?? statTitle ?? UUID().uuidString }

    private enum CodingKeys: String, CodingKey {
        case statId = "stat_id"
        case statTitle = "stat_title"
        case rows
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        statId = c.lenientString(.statId)
        statTitle = c.lenientString(.statTitle)
        rows = (try? c.decode([TautulliStatRow].self, forKey: .rows)) ?? []
    }
}

// MARK: - Users & libraries tables

public struct TautulliUserRow: Decodable, Sendable, Identifiable, Equatable, Hashable {
    public var userId: Int?
    public var friendlyName: String?
    public var plays: Int?
    public var duration: Int?
    public var lastSeen: Int?
    public var platform: String?
    public var mediaType: String?

    public var id: String { userId.map(String.init) ?? friendlyName ?? UUID().uuidString }
    public var lastSeenDate: Date? { lastSeen.map { Date(timeIntervalSince1970: TimeInterval($0)) } }

    private enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case friendlyName = "friendly_name"
        case plays, duration, platform
        case lastSeen = "last_seen"
        case mediaType = "media_type"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = c.lenientInt(.userId)
        friendlyName = c.lenientString(.friendlyName)
        plays = c.lenientInt(.plays)
        duration = c.lenientInt(.duration)
        lastSeen = c.lenientInt(.lastSeen)
        platform = c.lenientString(.platform)
        mediaType = c.lenientString(.mediaType)
    }
}

public struct TautulliUsersTable: Decodable, Sendable {
    public var data: [TautulliUserRow]
    private enum CodingKeys: String, CodingKey { case data }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data = (try? c.decode([TautulliUserRow].self, forKey: .data)) ?? []
    }
}

public struct TautulliLibraryRow: Decodable, Sendable, Identifiable, Equatable, Hashable {
    public var sectionId: Int?
    public var sectionName: String?
    public var sectionType: String?
    public var count: Int?
    public var childCount: Int?
    public var plays: Int?
    public var duration: Int?
    public var lastAccessed: Int?

    public var id: String { sectionId.map(String.init) ?? sectionName ?? UUID().uuidString }

    private enum CodingKeys: String, CodingKey {
        case sectionId = "section_id"
        case sectionName = "section_name"
        case sectionType = "section_type"
        case count, plays, duration
        case childCount = "child_count"
        case lastAccessed = "last_accessed"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sectionId = c.lenientInt(.sectionId)
        sectionName = c.lenientString(.sectionName)
        sectionType = c.lenientString(.sectionType)
        count = c.lenientInt(.count)
        childCount = c.lenientInt(.childCount)
        plays = c.lenientInt(.plays)
        duration = c.lenientInt(.duration)
        lastAccessed = c.lenientInt(.lastAccessed)
    }
}

public struct TautulliLibrariesTable: Decodable, Sendable {
    public var data: [TautulliLibraryRow]
    private enum CodingKeys: String, CodingKey { case data }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data = (try? c.decode([TautulliLibraryRow].self, forKey: .data)) ?? []
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

    /// Recent watch history (most recent first).
    public func history(length: Int = 25, userId: Int? = nil) async throws -> TautulliHistory {
        var params = [
            URLQueryItem(name: "length", value: String(length)),
            URLQueryItem(name: "order_column", value: "date"),
            URLQueryItem(name: "order_dir", value: "desc")
        ]
        if let userId { params.append(URLQueryItem(name: "user_id", value: String(userId))) }
        return try await call("get_history", params: params)
    }

    /// Home statistics groups (most watched movies/shows, most active users/platforms).
    public func homeStats(timeRange: Int = 30, statsCount: Int = 5) async throws -> [TautulliHomeStat] {
        try await call("get_home_stats", params: [
            URLQueryItem(name: "time_range", value: String(timeRange)),
            URLQueryItem(name: "stats_count", value: String(statsCount))
        ])
    }

    /// Per-user totals (plays, watch time, last seen).
    public func usersTable(length: Int = 50) async throws -> TautulliUsersTable {
        try await call("get_users_table", params: [
            URLQueryItem(name: "order_column", value: "last_seen"),
            URLQueryItem(name: "order_dir", value: "desc"),
            URLQueryItem(name: "length", value: String(length))
        ])
    }

    /// Per-library section totals (item counts, plays).
    public func librariesTable(length: Int = 50) async throws -> TautulliLibrariesTable {
        try await call("get_libraries_table", params: [
            URLQueryItem(name: "order_column", value: "section_name"),
            URLQueryItem(name: "order_dir", value: "asc"),
            URLQueryItem(name: "length", value: String(length))
        ])
    }

    /// Terminates an active stream. `message` is shown to the affected client.
    public func terminateSession(sessionKey: String, message: String? = nil) async throws {
        var params = [URLQueryItem(name: "session_key", value: sessionKey)]
        if let message, !message.isEmpty { params.append(URLQueryItem(name: "message", value: message)) }
        try await command("terminate_session", params: params)
    }

    /// Runs a command that returns no `data`, validating only the result status.
    private func command(_ cmd: String, params: [URLQueryItem] = []) async throws {
        var query = [URLQueryItem(name: "cmd", value: cmd)]
        query.append(contentsOf: params)
        let bare: TautulliBareEnvelope = try await api.send(.get("api/v2", query: query))
        guard bare.response.result == "success" else {
            throw APIError.server(statusCode: 200, body: bare.response.message ?? "Tautulli error")
        }
    }
}
