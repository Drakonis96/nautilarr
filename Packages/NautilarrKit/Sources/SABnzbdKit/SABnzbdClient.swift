import Foundation
import NautilarrCore

/// Client for the SABnzbd API. Authentication is via the `apikey` query
/// parameter (attached by `APIKeyQueryAuthorizer`), so it reuses the standard
/// `ServiceClientFactory`. All endpoints hang off `/api` with `mode=…`.
///
/// API reference (public, official): https://sabnzbd.org/wiki/configuration/4.0/api
public struct SABnzbdClient: Sendable {
    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public init(instance: ServiceInstance, credential: Credential, monitor: NetworkMonitor? = nil) {
        self.api = ServiceClientFactory.makeClient(for: instance, credential: credential, monitor: monitor)
    }

    private func endpoint(_ items: [String: String]) -> Endpoint {
        var query = items.map { URLQueryItem(name: $0.key, value: $0.value) }
        query.append(URLQueryItem(name: "output", value: "json"))
        return .get("api", query: query)
    }

    // MARK: Connection test
    public func version() async throws -> SABVersion {
        try await api.send(endpoint(["mode": "version"]))
    }

    // MARK: Queue
    public func queue() async throws -> SABQueue {
        let response: SABQueueResponse = try await api.send(endpoint(["mode": "queue"]))
        return response.queue
    }

    // MARK: Global controls
    public func pauseAll() async throws { _ = try await api.send(endpoint(["mode": "pause"])) }
    public func resumeAll() async throws { _ = try await api.send(endpoint(["mode": "resume"])) }

    /// Sets the speed limit as a percentage of the configured maximum (0–100),
    /// or an absolute value with a unit suffix (e.g. `"500K"`).
    public func setSpeedLimit(_ value: String) async throws {
        _ = try await api.send(endpoint(["mode": "config", "name": "speedlimit", "value": value]))
    }

    // MARK: Per-job controls
    public func pause(nzoId: String) async throws {
        _ = try await api.send(endpoint(["mode": "queue", "name": "pause", "value": nzoId]))
    }
    public func resume(nzoId: String) async throws {
        _ = try await api.send(endpoint(["mode": "queue", "name": "resume", "value": nzoId]))
    }
    public func delete(nzoId: String, deleteFiles: Bool = true) async throws {
        _ = try await api.send(endpoint([
            "mode": "queue", "name": "delete", "value": nzoId,
            "del_files": deleteFiles ? "1" : "0"
        ]))
    }

    /// Queues a download from an NZB URL (or magnet/news URL SAB understands).
    // VERIFY: mode=addurl&name=<url>.
    public func addURL(_ url: String) async throws {
        _ = try await api.send(endpoint(["mode": "addurl", "name": url]))
    }
}
