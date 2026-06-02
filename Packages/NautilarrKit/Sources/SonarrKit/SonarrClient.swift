import Foundation
import NautilarrCore

/// Typed client for the Sonarr v3 REST API (also serves Sonarr v4, which keeps
/// the `/api/v3` path). Wraps the generic `APIClient`, so it inherits host
/// failover, custom headers, self-signed TLS handling and error normalisation.
///
/// API reference (public, official): https://sonarr.tv/docs/api/
/// Authentication is via the `X-Api-Key` header, attached by the
/// `APIKeyHeaderAuthorizer` built in `AuthorizerFactory`.
public struct SonarrClient: Sendable {
    private let api: APIClient
    private static let base = "api/v3"

    public init(api: APIClient) {
        self.api = api
    }

    /// Builds a Sonarr client for an instance using its stored API key.
    public init(instance: ServiceInstance, credential: Credential, monitor: NetworkMonitor? = nil) {
        self.api = ServiceClientFactory.makeClient(for: instance, credential: credential, monitor: monitor)
    }

    // MARK: - System

    /// Connection test + version probe. Throws an `APIError` on failure.
    @discardableResult
    public func systemStatus() async throws -> SonarrSystemStatus {
        try await api.send(.get("\(Self.base)/system/status"))
    }

    public func health() async throws -> [SonarrHealthItem] {
        try await api.send(.get("\(Self.base)/health"))
    }

    // MARK: - Series

    public func series() async throws -> [SonarrSeries] {
        try await api.send(.get("\(Self.base)/series"))
    }

    public func series(id: Int) async throws -> SonarrSeries {
        try await api.send(.get("\(Self.base)/series/\(id)"))
    }

    /// Search the metadata provider for series to add (`/series/lookup`).
    public func lookupSeries(term: String) async throws -> [SonarrSeries] {
        try await api.send(.get("\(Self.base)/series/lookup", query: [URLQueryItem(name: "term", value: term)]))
    }

    /// Add a series to the library.
    public func addSeries(_ request: SonarrAddSeriesRequest) async throws -> SonarrSeries {
        let endpoint = try Endpoint.json("\(Self.base)/series", method: .post, body: request)
        return try await api.send(endpoint)
    }

    /// Delete a series, optionally removing files from disk.
    public func deleteSeries(id: Int, deleteFiles: Bool = false, addImportExclusion: Bool = false) async throws {
        let query = [
            URLQueryItem(name: "deleteFiles", value: String(deleteFiles)),
            URLQueryItem(name: "addImportListExclusion", value: String(addImportExclusion))
        ]
        try await api.send(.delete("\(Self.base)/series/\(id)", query: query))
    }

    // MARK: - Episodes

    public func episodes(seriesId: Int) async throws -> [SonarrEpisode] {
        try await api.send(.get("\(Self.base)/episode", query: [
            URLQueryItem(name: "seriesId", value: String(seriesId)),
            // Embed the linked file so the UI can show its media metadata.
            URLQueryItem(name: "includeEpisodeFile", value: "true")
        ]))
    }

    // MARK: - Queue

    /// Paged download queue. `includeSeries`/`includeEpisode` embed related
    /// objects so the UI can render titles without extra round-trips.
    public func queue(page: Int = 1, pageSize: Int = 50) async throws -> SonarrQueue {
        let query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "includeSeries", value: "true"),
            URLQueryItem(name: "includeEpisode", value: "true")
        ]
        return try await api.send(.get("\(Self.base)/queue", query: query))
    }

    /// Remove an item from the queue.
    public func removeQueueItem(id: Int, removeFromClient: Bool = true, blocklist: Bool = false) async throws {
        let query = [
            URLQueryItem(name: "removeFromClient", value: String(removeFromClient)),
            URLQueryItem(name: "blocklist", value: String(blocklist))
        ]
        try await api.send(.delete("\(Self.base)/queue/\(id)", query: query))
    }

    // MARK: - Interactive search (releases)

    /// Interactive search for releases for a specific episode.
    public func releases(episodeId: Int) async throws -> [SonarrRelease] {
        try await api.send(.get("\(Self.base)/release", query: [URLQueryItem(name: "episodeId", value: String(episodeId))]))
    }

    /// Interactive search for releases for an entire season.
    public func releases(seriesId: Int, seasonNumber: Int) async throws -> [SonarrRelease] {
        let query = [
            URLQueryItem(name: "seriesId", value: String(seriesId)),
            URLQueryItem(name: "seasonNumber", value: String(seasonNumber))
        ]
        return try await api.send(.get("\(Self.base)/release", query: query))
    }

    /// Push a chosen release to the download client.
    public func grab(_ release: SonarrRelease) async throws {
        guard let guid = release.guid, let indexerId = release.indexerId else {
            throw APIError.invalidResponse
        }
        let endpoint = try Endpoint.json(
            "\(Self.base)/release",
            method: .post,
            body: SonarrGrabReleaseRequest(guid: guid, indexerId: indexerId)
        )
        try await api.send(endpoint)
    }

    // MARK: - Commands (automatic search, refresh)

    @discardableResult
    public func runCommand(_ command: SonarrCommandRequest) async throws -> SonarrCommandResource {
        let endpoint = try Endpoint.json("\(Self.base)/command", method: .post, body: command)
        return try await api.send(endpoint)
    }

    // MARK: - Editing (monitored / quality profile / root folder)

    /// Bulk-edits one or more series via the editor endpoint. Only the non-nil
    /// fields are changed, so this serves both single-item and multi-item edits.
    /// Pass a new `rootFolderPath` with `moveFiles: true` to physically relocate
    /// the existing files.
    // VERIFY: PUT /api/v3/series/editor accepts { seriesIds, monitored, qualityProfileId, rootFolderPath, moveFiles }.
    public func editSeries(
        ids: [Int],
        monitored: Bool? = nil,
        qualityProfileId: Int? = nil,
        rootFolderPath: String? = nil,
        moveFiles: Bool = false
    ) async throws {
        let body = SonarrSeriesEditorRequest(
            seriesIds: ids, monitored: monitored, qualityProfileId: qualityProfileId,
            rootFolderPath: rootFolderPath, moveFiles: rootFolderPath == nil ? nil : moveFiles
        )
        let endpoint = try Endpoint.json("\(Self.base)/series/editor", method: .put, body: body)
        try await api.send(endpoint)
    }

    /// Replaces a single series resource. Used for season monitoring (which the
    /// editor endpoint doesn't cover): flip a season's `monitored` on a fetched
    /// series and PUT it back.
    // VERIFY: PUT /api/v3/series/{id} accepts the full series resource.
    @discardableResult
    public func updateSeries(_ series: SonarrSeries) async throws -> SonarrSeries {
        let endpoint = try Endpoint.json("\(Self.base)/series/\(series.id)", method: .put, body: series)
        return try await api.send(endpoint)
    }

    /// Toggles monitoring on individual episodes.
    // VERIFY: PUT /api/v3/episode/monitor accepts { episodeIds, monitored }.
    public func setEpisodesMonitored(ids: [Int], monitored: Bool) async throws {
        let body = SonarrEpisodeMonitorRequest(episodeIds: ids, monitored: monitored)
        let endpoint = try Endpoint.json("\(Self.base)/episode/monitor", method: .put, body: body)
        try await api.send(endpoint)
    }

    // MARK: - Calendar

    /// Upcoming episodes between two dates. `unmonitored: true` includes episodes
    /// of unmonitored series/seasons so the calendar shows ALL upcoming releases
    /// (the API omits them by default, which is why future items can look absent).
    public func calendar(start: Date, end: Date, includeSeries: Bool = true, unmonitored: Bool = false) async throws -> [SonarrEpisode] {
        let formatter = ISO8601DateFormatter()
        let query = [
            URLQueryItem(name: "start", value: formatter.string(from: start)),
            URLQueryItem(name: "end", value: formatter.string(from: end)),
            URLQueryItem(name: "includeSeries", value: String(includeSeries)),
            URLQueryItem(name: "unmonitored", value: String(unmonitored))
        ]
        return try await api.send(.get("\(Self.base)/calendar", query: query))
    }

    // MARK: - History

    public func history(page: Int = 1, pageSize: Int = 50) async throws -> SonarrHistory {
        let query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "sortKey", value: "date"),
            URLQueryItem(name: "sortDirection", value: "descending"),
            URLQueryItem(name: "includeSeries", value: "true"),
            URLQueryItem(name: "includeEpisode", value: "true")
        ]
        return try await api.send(.get("\(Self.base)/history", query: query))
    }

    // MARK: - Profiles & folders (needed to add a series)

    public func qualityProfiles() async throws -> [SonarrQualityProfile] {
        try await api.send(.get("\(Self.base)/qualityprofile"))
    }

    /// Language profiles exist only in Sonarr v3. Returns an empty list (not an
    /// error) on versions where the endpoint is absent.
    public func languageProfiles() async throws -> [SonarrLanguageProfile] {
        do {
            return try await api.send(.get("\(Self.base)/languageprofile"))
        } catch APIError.notFound {
            return []
        }
    }

    public func rootFolders() async throws -> [SonarrRootFolder] {
        try await api.send(.get("\(Self.base)/rootfolder"))
    }
}
