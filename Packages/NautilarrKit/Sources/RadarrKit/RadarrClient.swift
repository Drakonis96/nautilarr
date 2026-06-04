import Foundation
import NautilarrCore

/// Typed client for the Radarr v3 REST API. Mirrors `SonarrClient` for the movie
/// domain, reusing the generic `APIClient` (failover, headers, self-signed TLS,
/// error normalisation). Authentication is via the `X-Api-Key` header.
///
/// API reference (public, official): https://radarr.video/docs/api/
public struct RadarrClient: Sendable {
    private let api: APIClient
    private static let base = "api/v3"

    public init(api: APIClient) { self.api = api }

    public init(instance: ServiceInstance, credential: Credential, monitor: NetworkMonitor? = nil) {
        self.api = ServiceClientFactory.makeClient(for: instance, credential: credential, monitor: monitor)
    }

    // MARK: System
    @discardableResult
    public func systemStatus() async throws -> RadarrSystemStatus {
        try await api.send(.get("\(Self.base)/system/status"))
    }
    public func health() async throws -> [RadarrHealthItem] {
        try await api.send(.get("\(Self.base)/health"))
    }

    // MARK: Movies
    public func movies() async throws -> [RadarrMovie] {
        try await api.send(.get("\(Self.base)/movie"))
    }
    public func movie(id: Int) async throws -> RadarrMovie {
        try await api.send(.get("\(Self.base)/movie/\(id)"))
    }
    public func lookupMovies(term: String) async throws -> [RadarrMovie] {
        try await api.send(.get("\(Self.base)/movie/lookup", query: [URLQueryItem(name: "term", value: term)]))
    }
    public func addMovie(_ request: RadarrAddMovieRequest) async throws -> RadarrMovie {
        try await api.send(try Endpoint.json("\(Self.base)/movie", method: .post, body: request))
    }
    public func deleteMovie(id: Int, deleteFiles: Bool = false, addImportExclusion: Bool = false) async throws {
        let query = [
            URLQueryItem(name: "deleteFiles", value: String(deleteFiles)),
            URLQueryItem(name: "addImportExclusion", value: String(addImportExclusion))
        ]
        try await api.send(.delete("\(Self.base)/movie/\(id)", query: query))
    }

    // MARK: Queue
    public func queue(page: Int = 1, pageSize: Int = 50) async throws -> RadarrQueue {
        let query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "includeMovie", value: "true")
        ]
        return try await api.send(.get("\(Self.base)/queue", query: query))
    }
    public func removeQueueItem(id: Int, removeFromClient: Bool = true, blocklist: Bool = false) async throws {
        let query = [
            URLQueryItem(name: "removeFromClient", value: String(removeFromClient)),
            URLQueryItem(name: "blocklist", value: String(blocklist))
        ]
        try await api.send(.delete("\(Self.base)/queue/\(id)", query: query))
    }

    // MARK: Interactive search
    public func releases(movieId: Int) async throws -> [RadarrRelease] {
        try await api.send(.get("\(Self.base)/release", query: [URLQueryItem(name: "movieId", value: String(movieId))]))
    }
    public func grab(_ release: RadarrRelease) async throws {
        guard let guid = release.guid, let indexerId = release.indexerId else { throw APIError.invalidResponse }
        try await api.send(try Endpoint.json(
            "\(Self.base)/release", method: .post,
            body: RadarrGrabReleaseRequest(guid: guid, indexerId: indexerId)
        ))
    }

    // MARK: Commands
    @discardableResult
    public func runCommand(_ command: RadarrCommandRequest) async throws -> RadarrCommandResource {
        try await api.send(try Endpoint.json("\(Self.base)/command", method: .post, body: command))
    }

    /// Re-processes monitored downloads, re-triggering import of completed items.
    // VERIFY: POST /api/v3/command { name: "RefreshMonitoredDownloads" }.
    @discardableResult
    public func refreshMonitoredDownloads() async throws -> RadarrCommandResource {
        try await runCommand(RadarrCommandRequest(name: "RefreshMonitoredDownloads"))
    }

    // MARK: Editing (monitored / quality profile / root folder)

    /// Bulk-edits one or more movies via the editor endpoint. Only the non-nil
    /// fields are changed, so it serves both single- and multi-item edits. Pass a
    /// new `rootFolderPath` with `moveFiles: true` to physically relocate files.
    // VERIFY: PUT /api/v3/movie/editor accepts { movieIds, monitored, qualityProfileId, rootFolderPath, moveFiles }.
    public func editMovies(
        ids: [Int],
        monitored: Bool? = nil,
        qualityProfileId: Int? = nil,
        rootFolderPath: String? = nil,
        moveFiles: Bool = false
    ) async throws {
        let body = RadarrMovieEditorRequest(
            movieIds: ids, monitored: monitored, qualityProfileId: qualityProfileId,
            rootFolderPath: rootFolderPath, moveFiles: rootFolderPath == nil ? nil : moveFiles
        )
        let endpoint = try Endpoint.json("\(Self.base)/movie/editor", method: .put, body: body)
        try await api.send(endpoint)
    }

    // MARK: Calendar
    /// Upcoming movies between two dates. `unmonitored: true` includes unmonitored
    /// movies so future releases aren't hidden (the API omits them by default).
    public func calendar(start: Date, end: Date, unmonitored: Bool = false) async throws -> [RadarrMovie] {
        let f = ISO8601DateFormatter()
        let query = [
            URLQueryItem(name: "start", value: f.string(from: start)),
            URLQueryItem(name: "end", value: f.string(from: end)),
            URLQueryItem(name: "unmonitored", value: String(unmonitored))
        ]
        return try await api.send(.get("\(Self.base)/calendar", query: query))
    }

    // MARK: Profiles & folders
    public func qualityProfiles() async throws -> [RadarrQualityProfile] {
        try await api.send(.get("\(Self.base)/qualityprofile"))
    }
    public func rootFolders() async throws -> [RadarrRootFolder] {
        try await api.send(.get("\(Self.base)/rootfolder"))
    }

    // MARK: - Download clients

    /// Download clients configured inside this Radarr instance.
    public func downloadClients() async throws -> [ArrDownloadClient] {
        try await api.send(.get("\(Self.base)/downloadclient"))
    }

    /// Enables or disables one of Radarr's download clients. Fetches the full
    /// client JSON, flips `enable` and PUTs it back, so every field the minimal
    /// `ArrDownloadClient` model doesn't map is preserved.
    public func setDownloadClientEnabled(id: Int, enabled: Bool) async throws {
        let data = try await api.sendReturningData(.get("\(Self.base)/downloadclient/\(id)"))
        guard var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        dict["enable"] = enabled
        let endpoint = try Endpoint.jsonObject("\(Self.base)/downloadclient/\(id)", method: .put, object: dict)
        try await api.send(endpoint)
    }

    /// Tests one of Radarr's download clients. Throws on failure.
    public func testDownloadClient(id: Int) async throws {
        let data = try await api.sendReturningData(.get("\(Self.base)/downloadclient/\(id)"))
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        let endpoint = try Endpoint.jsonObject("\(Self.base)/downloadclient/test", method: .post, object: dict)
        try await api.send(endpoint)
    }
}
