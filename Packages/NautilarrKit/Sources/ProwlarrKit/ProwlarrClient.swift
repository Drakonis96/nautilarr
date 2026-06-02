import Foundation
import NautilarrCore

// MARK: - Models

public struct ProwlarrSystemStatus: Codable, Sendable, Equatable {
    public var version: String?
    public var appName: String?
    public var instanceName: String?
}

public struct ProwlarrHealthItem: Codable, Sendable, Equatable, Identifiable {
    public var id: Int { (source?.hashValue ?? 0) ^ (message?.hashValue ?? 0) }
    public var source: String?
    public var type: String?
    public var message: String?
    public var wikiUrl: String?

    public enum Severity: String, Sendable { case ok, notice, warning, error, unknown }
    public var severity: Severity { Severity(rawValue: type?.lowercased() ?? "") ?? .unknown }
}

/// An indexer managed by Prowlarr.
public struct ProwlarrIndexer: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var name: String?
    public var enable: Bool?
    /// `usenet` or `torrent`.
    public var protocolName: String?
    public var privacy: String?
    public var priority: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, enable, privacy, priority
        case protocolName = "protocol"
    }
}

public struct ProwlarrCategory: Codable, Sendable, Equatable, Hashable {
    public var id: Int?
    public var name: String?
}

/// A release returned by a manual Prowlarr search across its indexers.
public struct ProwlarrSearchResult: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { guid ?? "\(indexerId ?? 0)-\(title ?? "")" }
    public var guid: String?
    public var title: String?
    public var size: Int64?
    public var indexer: String?
    public var indexerId: Int?
    public var seeders: Int?
    public var leechers: Int?
    public var grabs: Int?
    public var downloadUrl: String?
    public var infoUrl: String?
    public var protocolName: String?
    public var publishDate: Date?
    public var categories: [ProwlarrCategory]?

    private enum CodingKeys: String, CodingKey {
        case guid, title, size, indexer, indexerId, seeders, leechers, grabs
        case downloadUrl, infoUrl, publishDate, categories
        case protocolName = "protocol"
    }
}

/// Body for grabbing a search result (`POST /api/v1/search`).
public struct ProwlarrGrabRequest: Codable, Sendable {
    public var guid: String
    public var indexerId: Int
    public init(guid: String, indexerId: Int) { self.guid = guid; self.indexerId = indexerId }
}

// MARK: - Client

/// Client for the Prowlarr v1 API (indexer manager). `X-Api-Key` header auth via
/// `ServiceClientFactory`.
///
/// API reference (public, official): https://prowlarr.com/docs/api/
public struct ProwlarrClient: Sendable {
    private let api: APIClient
    private static let base = "api/v1"

    public init(api: APIClient) { self.api = api }

    public init(instance: ServiceInstance, credential: Credential, monitor: NetworkMonitor? = nil) {
        self.api = ServiceClientFactory.makeClient(for: instance, credential: credential, monitor: monitor)
    }

    @discardableResult
    public func systemStatus() async throws -> ProwlarrSystemStatus {
        try await api.send(.get("\(Self.base)/system/status"))
    }
    public func health() async throws -> [ProwlarrHealthItem] {
        try await api.send(.get("\(Self.base)/health"))
    }
    public func indexers() async throws -> [ProwlarrIndexer] {
        try await api.send(.get("\(Self.base)/indexer"))
    }

    /// Manual search across all (or the given) indexers.
    // VERIFY: GET /api/v1/search?query=&type=search&indexerIds=&limit=.
    public func search(query: String, indexerIds: [Int]? = nil, limit: Int = 100) async throws -> [ProwlarrSearchResult] {
        var items = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "type", value: "search"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let indexerIds, !indexerIds.isEmpty {
            items.append(URLQueryItem(name: "indexerIds", value: indexerIds.map(String.init).joined(separator: ",")))
        }
        return try await api.send(.get("\(Self.base)/search", query: items))
    }

    /// Pushes a chosen search result to Prowlarr's configured download client.
    // VERIFY: POST /api/v1/search with { guid, indexerId } grabs the release.
    public func grab(_ result: ProwlarrSearchResult) async throws {
        guard let guid = result.guid, let indexerId = result.indexerId else { throw APIError.invalidResponse }
        let endpoint = try Endpoint.json("\(Self.base)/search", method: .post,
                                         body: ProwlarrGrabRequest(guid: guid, indexerId: indexerId))
        try await api.send(endpoint)
    }

    /// Enables or disables an indexer. Fetches the full indexer JSON, flips
    /// `enable` and PUTs it back, so every field the minimal `ProwlarrIndexer`
    /// model doesn't map is preserved (avoids a lossy round-trip).
    // VERIFY: GET + PUT /api/v1/indexer/{id}.
    public func setIndexerEnabled(id: Int, enabled: Bool) async throws {
        let data = try await api.sendReturningData(.get("\(Self.base)/indexer/\(id)"))
        guard var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        dict["enable"] = enabled
        let endpoint = try Endpoint.jsonObject("\(Self.base)/indexer/\(id)", method: .put, object: dict)
        try await api.send(endpoint)
    }

    /// Tests an indexer's connectivity. Throws on failure.
    // VERIFY: POST /api/v1/indexer/test with the full indexer body.
    public func testIndexer(id: Int) async throws {
        let data = try await api.sendReturningData(.get("\(Self.base)/indexer/\(id)"))
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        let endpoint = try Endpoint.jsonObject("\(Self.base)/indexer/test", method: .post, object: dict)
        try await api.send(endpoint)
    }
}
