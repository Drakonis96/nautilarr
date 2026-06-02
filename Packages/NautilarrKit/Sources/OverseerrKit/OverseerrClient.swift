import Foundation
import NautilarrCore

/// Client for the Overseerr / Jellyseerr API (v1). Authentication is via the
/// `X-Api-Key` header (reuses `ServiceClientFactory`).
///
/// API reference (public, official): https://api-docs.overseerr.dev
public struct OverseerrClient: Sendable {
    private let api: APIClient
    private static let base = "api/v1"

    public init(api: APIClient) { self.api = api }

    public init(instance: ServiceInstance, credential: Credential, monitor: NetworkMonitor? = nil) {
        self.api = ServiceClientFactory.makeClient(for: instance, credential: credential, monitor: monitor)
    }

    // MARK: Connection test
    public func status() async throws -> OverseerrStatus {
        try await api.send(.get("\(Self.base)/status"))
    }

    // MARK: Requests
    public func requests(take: Int = 20, skip: Int = 0, filter: String = "all", sort: String = "added") async throws -> OverseerrRequestPage {
        let query = [
            URLQueryItem(name: "take", value: String(take)),
            URLQueryItem(name: "skip", value: String(skip)),
            URLQueryItem(name: "filter", value: filter),
            URLQueryItem(name: "sort", value: sort)
        ]
        return try await api.send(.get("\(Self.base)/request", query: query))
    }

    public func requestCount() async throws -> OverseerrRequestCount {
        try await api.send(.get("\(Self.base)/request/count"))
    }

    @discardableResult
    public func approve(requestId: Int) async throws -> OverseerrRequest {
        try await api.send(Endpoint(path: "\(Self.base)/request/\(requestId)/approve", method: .post))
    }

    @discardableResult
    public func decline(requestId: Int) async throws -> OverseerrRequest {
        try await api.send(Endpoint(path: "\(Self.base)/request/\(requestId)/decline", method: .post))
    }

    public func deleteRequest(requestId: Int) async throws {
        try await api.send(.delete("\(Self.base)/request/\(requestId)"))
    }

    // MARK: Media details (title/artwork enrichment)
    public func mediaDetails(mediaType: String, tmdbId: Int) async throws -> OverseerrMediaDetails {
        let path = mediaType == "tv" ? "tv" : "movie"
        return try await api.send(.get("\(Self.base)/\(path)/\(tmdbId)"))
    }

    // MARK: Discover / create requests

    /// Multi-search for titles to request. Drops `person` results.
    public func search(query: String, page: Int = 1) async throws -> [OverseerrSearchResult] {
        let items = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: String(page))
        ]
        let result: OverseerrSearchPage = try await api.send(.get("\(Self.base)/search", query: items))
        return result.results.filter { $0.mediaType == "movie" || $0.mediaType == "tv" }
    }

    // MARK: Advanced request options (servers / profiles / root folders)

    /// The Radarr (movie) or Sonarr (TV) servers Overseerr can route to.
    // VERIFY: GET /api/v1/service/{radarr|sonarr}.
    public func servers(forTV: Bool) async throws -> [OverseerrServer] {
        let kind = forTV ? "sonarr" : "radarr"
        return try await api.send(.get("\(Self.base)/service/\(kind)"))
    }

    /// Quality profiles, root folders and (Sonarr) language profiles for a server.
    // VERIFY: GET /api/v1/service/{radarr|sonarr}/{serverId}.
    public func serverDetails(forTV: Bool, serverId: Int) async throws -> OverseerrServerDetails {
        let kind = forTV ? "sonarr" : "radarr"
        return try await api.send(.get("\(Self.base)/service/\(kind)/\(serverId)"))
    }

    /// Creates a request for a title, optionally overriding the destination
    /// server, quality/language profile, root folder, 4K and TV seasons — the
    /// same advanced options Overseerr's own request dialog offers. Omitted
    /// options fall back to Overseerr's defaults.
    // VERIFY: POST /api/v1/request body shape.
    public func createRequest(
        mediaType: String,
        mediaId: Int,
        seasons: [Int]? = nil,
        allSeasons: Bool = true,
        is4k: Bool = false,
        serverId: Int? = nil,
        profileId: Int? = nil,
        rootFolder: String? = nil,
        languageProfileId: Int? = nil
    ) async throws {
        var object: [String: Any] = ["mediaType": mediaType, "mediaId": mediaId]
        if mediaType == "tv" {
            if let seasons, !seasons.isEmpty { object["seasons"] = seasons }
            else if allSeasons { object["seasons"] = "all" }
        }
        if is4k { object["is4k"] = true }
        if let serverId { object["serverId"] = serverId }
        if let profileId { object["profileId"] = profileId }
        if let rootFolder { object["rootFolder"] = rootFolder }
        if let languageProfileId { object["languageProfileId"] = languageProfileId }
        let endpoint = try Endpoint.jsonObject("\(Self.base)/request", method: .post, object: object)
        try await api.send(endpoint)
    }
}
