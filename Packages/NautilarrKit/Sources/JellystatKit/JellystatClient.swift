import Foundation
import NautilarrCore

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
}
