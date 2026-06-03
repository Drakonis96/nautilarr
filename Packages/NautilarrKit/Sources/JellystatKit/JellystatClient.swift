import Foundation
import NautilarrCore

// MARK: - Lenient decoding helpers

/// Jellystat's Postgres-backed stats can surface numbers as JSON numbers or
/// strings depending on the column/version, so decode tolerantly.
private extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return String(d) }
        return nil
    }
    func lenientInt(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int(Double(s) ?? 0) }
        return nil
    }
    /// First key that yields a value, across alternate spellings.
    func lenientString(_ keys: [Key]) -> String? {
        for k in keys { if let v = lenientString(k) { return v } }
        return nil
    }
    func lenientInt(_ keys: [Key]) -> Int? {
        for k in keys { if let v = lenientInt(k) { return v } }
        return nil
    }
}

// MARK: - Models (Jellyfin session shape, proxied by Jellystat)

public struct JellystatNowPlaying: Codable, Sendable, Equatable, Hashable {
    public var name: String?
    public var seriesName: String?
    public var type: String?
    public var runTimeTicks: Int64?

    private enum CodingKeys: String, CodingKey {
        case name = "Name"
        case seriesName = "SeriesName"
        case type = "Type"
        case runTimeTicks = "RunTimeTicks"
    }
}

public struct JellystatPlayState: Codable, Sendable, Equatable, Hashable {
    public var positionTicks: Int64?
    public var isPaused: Bool?

    private enum CodingKeys: String, CodingKey {
        case positionTicks = "PositionTicks"
        case isPaused = "IsPaused"
    }
}

/// A live session from `/proxy/getSessions` (Jellystat proxies Jellyfin).
public struct JellystatSession: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { sessionId ?? "\(userName ?? "")-\(nowPlayingItem?.name ?? "")" }
    public var sessionId: String?
    public var userName: String?
    public var client: String?
    public var deviceName: String?
    public var nowPlayingItem: JellystatNowPlaying?
    public var playState: JellystatPlayState?

    private enum CodingKeys: String, CodingKey {
        case sessionId = "Id"
        case userName = "UserName"
        case client = "Client"
        case deviceName = "DeviceName"
        case nowPlayingItem = "NowPlayingItem"
        case playState = "PlayState"
    }

    /// Only sessions that are actually playing something.
    public var isPlaying: Bool { nowPlayingItem != nil }
    public var isPaused: Bool { playState?.isPaused ?? false }
    public var displayTitle: String {
        if let series = nowPlayingItem?.seriesName, let name = nowPlayingItem?.name {
            return "\(series) — \(name)"
        }
        return nowPlayingItem?.name ?? "Unknown"
    }
    public var progress: Double {
        guard let total = nowPlayingItem?.runTimeTicks, total > 0,
              let pos = playState?.positionTicks else { return 0 }
        return max(0, min(1, Double(pos) / Double(total)))
    }
}

// MARK: - Stats models

/// Per-user activity from `/stats/getAllUserActivity` (the `jf_all_user_activity`
/// view). `TotalWatchTime` is in seconds.
public struct JellystatUserActivity: Decodable, Sendable, Identifiable, Equatable, Hashable {
    public var userId: String?
    public var userName: String?
    public var totalPlays: Int?
    public var totalWatchTime: Int?
    public var lastClient: String?
    public var lastActivityDate: String?

    public var id: String { userId ?? userName ?? UUID().uuidString }

    private enum CodingKeys: String, CodingKey {
        case userId = "UserId"
        case userName = "UserName"
        case totalPlays = "TotalPlays"
        case totalWatchTime = "TotalWatchTime"
        case lastClient = "LastClient"
        case lastActivityDate = "LastActivityDate"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = c.lenientString(.userId)
        userName = c.lenientString(.userName)
        totalPlays = c.lenientInt(.totalPlays)
        totalWatchTime = c.lenientInt(.totalWatchTime)
        lastClient = c.lenientString(.lastClient)
        lastActivityDate = c.lenientString(.lastActivityDate)
    }
}

/// Per-library stats from `/stats/getLibraryCardStats`
/// (the `js_library_stats_overview` view).
public struct JellystatLibraryCard: Decodable, Sendable, Identifiable, Equatable, Hashable {
    public var libraryId: String?
    public var name: String?
    public var collectionType: String?
    public var libraryCount: Int?
    public var seasonCount: Int?
    public var episodeCount: Int?

    public var id: String { libraryId ?? name ?? UUID().uuidString }

    private enum CodingKeys: String, CodingKey {
        case libraryId = "Id"
        case name = "Name"
        case collectionType = "CollectionType"
        case libraryCount = "Library_Count"
        case seasonCount = "Season_Count"
        case episodeCount = "Episode_Count"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        libraryId = c.lenientString(.libraryId)
        name = c.lenientString(.name)
        collectionType = c.lenientString(.collectionType)
        libraryCount = c.lenientInt(.libraryCount)
        seasonCount = c.lenientInt(.seasonCount)
        episodeCount = c.lenientInt(.episodeCount)
    }
}

/// A ranked entry from the `/stats/getMostViewedByType` and
/// `/stats/getMostActiveUsers` endpoints (item or user + play count).
public struct JellystatRanked: Decodable, Sendable, Identifiable, Equatable, Hashable {
    public var entryId: String?
    public var name: String?
    public var plays: Int?

    public var id: String { entryId ?? name ?? UUID().uuidString }

    private enum CodingKeys: String, CodingKey {
        case id = "Id", userId = "UserId"
        case name = "Name", userName = "UserName"
        case plays = "Plays"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entryId = c.lenientString([.id, .userId])
        name = c.lenientString([.name, .userName])
        plays = c.lenientInt([.plays])
    }
}

// MARK: - Client

/// Client for the Jellystat API (Jellyfin monitoring). Authentication is via the
/// `x-api-token` header (attached by `ServiceClientFactory`).
///
/// VERIFY: the API-key header name (`x-api-token`) and the exact session shape
/// against your Jellystat version's `/swagger`.
public struct JellystatClient: Sendable {
    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public init(instance: ServiceInstance, credential: Credential, monitor: NetworkMonitor? = nil) {
        self.api = ServiceClientFactory.makeClient(for: instance, credential: credential, monitor: monitor)
    }

    /// Connection test — reaching `getLibraries` confirms host + key.
    public func testReachable() async throws {
        _ = try await api.sendReturningData(.get("api/getLibraries"))
    }

    /// Currently-playing Jellyfin sessions.
    public func sessions() async throws -> [JellystatSession] {
        let all: [JellystatSession] = try await api.send(.get("proxy/getSessions"))
        return all.filter { $0.isPlaying }
    }

    /// Per-user activity totals (`/stats/getAllUserActivity`).
    public func users() async throws -> [JellystatUserActivity] {
        try await api.send(.get("stats/getAllUserActivity"))
    }

    /// Per-library stats cards (`/stats/getLibraryCardStats`).
    public func libraryCards() async throws -> [JellystatLibraryCard] {
        try await api.send(.get("stats/getLibraryCardStats"))
    }

    /// Most-viewed items of a given type over the last `days`. `type` is one of
    /// "Movie", "Series" or "Audio".
    public func mostViewed(type: String, days: Int = 30) async throws -> [JellystatRanked] {
        let endpoint = try Endpoint.jsonObject("stats/getMostViewedByType", method: .post,
                                               object: ["days": days, "type": type])
        return try await api.send(endpoint)
    }

    /// Most-active users over the last `days`.
    public func mostActiveUsers(days: Int = 30) async throws -> [JellystatRanked] {
        let endpoint = try Endpoint.jsonObject("stats/getMostActiveUsers", method: .post,
                                               object: ["days": days])
        return try await api.send(endpoint)
    }
}
