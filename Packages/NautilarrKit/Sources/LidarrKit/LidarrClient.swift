import Foundation
import NautilarrCore

/// Typed client for the Lidarr v1 REST API (music: artists & albums). Reuses the
/// generic `APIClient`. Authentication is via the `X-Api-Key` header.
///
/// API reference (public, official): https://lidarr.audio/docs/api/
public struct LidarrClient: Sendable {
    private let api: APIClient
    private static let base = "api/v1"

    public init(api: APIClient) { self.api = api }

    public init(instance: ServiceInstance, credential: Credential, monitor: NetworkMonitor? = nil) {
        self.api = ServiceClientFactory.makeClient(for: instance, credential: credential, monitor: monitor)
    }

    // MARK: System
    @discardableResult
    public func systemStatus() async throws -> LidarrSystemStatus {
        try await api.send(.get("\(Self.base)/system/status"))
    }
    public func health() async throws -> [LidarrHealthItem] {
        try await api.send(.get("\(Self.base)/health"))
    }

    // MARK: Artists
    public func artists() async throws -> [LidarrArtist] {
        try await api.send(.get("\(Self.base)/artist"))
    }
    public func artist(id: Int) async throws -> LidarrArtist {
        try await api.send(.get("\(Self.base)/artist/\(id)"))
    }
    public func lookupArtists(term: String) async throws -> [LidarrArtist] {
        try await api.send(.get("\(Self.base)/artist/lookup", query: [URLQueryItem(name: "term", value: term)]))
    }
    public func addArtist(_ request: LidarrAddArtistRequest) async throws -> LidarrArtist {
        try await api.send(try Endpoint.json("\(Self.base)/artist", method: .post, body: request))
    }
    public func deleteArtist(id: Int, deleteFiles: Bool = false) async throws {
        let query = [URLQueryItem(name: "deleteFiles", value: String(deleteFiles))]
        try await api.send(.delete("\(Self.base)/artist/\(id)", query: query))
    }

    // MARK: Albums
    public func albums(artistId: Int) async throws -> [LidarrAlbum] {
        try await api.send(.get("\(Self.base)/album", query: [URLQueryItem(name: "artistId", value: String(artistId))]))
    }

    // MARK: Queue
    public func queue(page: Int = 1, pageSize: Int = 50) async throws -> LidarrQueue {
        let query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "includeArtist", value: "true"),
            URLQueryItem(name: "includeAlbum", value: "true")
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
    public func releases(albumId: Int) async throws -> [LidarrRelease] {
        try await api.send(.get("\(Self.base)/release", query: [URLQueryItem(name: "albumId", value: String(albumId))]))
    }
    public func grab(_ release: LidarrRelease) async throws {
        guard let guid = release.guid, let indexerId = release.indexerId else { throw APIError.invalidResponse }
        try await api.send(try Endpoint.json(
            "\(Self.base)/release", method: .post,
            body: LidarrGrabReleaseRequest(guid: guid, indexerId: indexerId)
        ))
    }

    // MARK: Commands
    @discardableResult
    public func runCommand(_ command: LidarrCommandRequest) async throws -> LidarrCommandResource {
        try await api.send(try Endpoint.json("\(Self.base)/command", method: .post, body: command))
    }

    // MARK: Editing (monitored / quality profile / root folder)

    /// Bulk-edits one or more artists via the editor endpoint. Only the non-nil
    /// fields change, so it serves both single- and multi-item edits. Pass a new
    /// `rootFolderPath` with `moveFiles: true` to physically relocate files.
    // VERIFY: PUT /api/v1/artist/editor accepts { artistIds, monitored, qualityProfileId, metadataProfileId, rootFolderPath, moveFiles }.
    public func editArtists(
        ids: [Int],
        monitored: Bool? = nil,
        qualityProfileId: Int? = nil,
        metadataProfileId: Int? = nil,
        rootFolderPath: String? = nil,
        moveFiles: Bool = false
    ) async throws {
        let body = LidarrArtistEditorRequest(
            artistIds: ids, monitored: monitored, qualityProfileId: qualityProfileId,
            metadataProfileId: metadataProfileId, rootFolderPath: rootFolderPath,
            moveFiles: rootFolderPath == nil ? nil : moveFiles
        )
        let endpoint = try Endpoint.json("\(Self.base)/artist/editor", method: .put, body: body)
        try await api.send(endpoint)
    }

    /// Toggles monitoring on individual albums.
    // VERIFY: PUT /api/v1/album/monitor accepts { albumIds, monitored }.
    public func setAlbumsMonitored(ids: [Int], monitored: Bool) async throws {
        let body = LidarrAlbumMonitorRequest(albumIds: ids, monitored: monitored)
        let endpoint = try Endpoint.json("\(Self.base)/album/monitor", method: .put, body: body)
        try await api.send(endpoint)
    }

    // MARK: Profiles & folders
    public func qualityProfiles() async throws -> [LidarrQualityProfile] {
        try await api.send(.get("\(Self.base)/qualityprofile"))
    }
    public func metadataProfiles() async throws -> [LidarrMetadataProfile] {
        try await api.send(.get("\(Self.base)/metadataprofile"))
    }
    public func rootFolders() async throws -> [LidarrRootFolder] {
        try await api.send(.get("\(Self.base)/rootfolder"))
    }
}
