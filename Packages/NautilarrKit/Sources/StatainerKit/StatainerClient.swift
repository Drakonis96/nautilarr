import Foundation
import NautilarrCore

/// Client for the Statainer external API — a self-hosted Docker dashboard.
///
/// Talks to the `/api/v1` surface using the `X-API-Key` header (Statainer also
/// accepts `Authorization: Bearer`, but the header form maps cleanly onto the
/// app's existing API-key authorizer). Exposes the host overview, container
/// metadata, live per-container metrics and the lifecycle actions
/// (start/stop/restart/update).
///
/// API reference (public, official):
/// https://github.com/Drakonis96/statainer/blob/main/API.md
public struct StatainerClient: Sendable {
    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public init(instance: ServiceInstance, credential: Credential, monitor: NetworkMonitor? = nil) {
        self.api = ServiceClientFactory.makeClient(for: instance, credential: credential, monitor: monitor)
    }

    // MARK: - Reads

    /// Liveness probe (`GET /api/v1/ping`) — needs only a valid token, so it's the
    /// cheapest connection test.
    @discardableResult
    public func ping() async throws -> StatainerPing {
        try await api.send(Endpoint.get("api/v1/ping"))
    }

    /// Host + Docker overview (`GET /api/v1/system`).
    public func system() async throws -> StatainerSystem {
        try await api.send(Endpoint.get("api/v1/system"))
    }

    /// Container metadata (`GET /api/v1/containers`): image, ports, uptime,
    /// update availability, compose project/service.
    public func containers() async throws -> [StatainerContainer] {
        let list: StatainerContainerList = try await api.send(Endpoint.get("api/v1/containers"))
        return list.containers
    }

    /// Live per-container metrics (`GET /api/v1/stats`): CPU %, memory, net/block
    /// I/O, PID count.
    public func stats() async throws -> [StatainerContainer] {
        let list: StatainerStatsList = try await api.send(Endpoint.get("api/v1/stats"))
        return list.containers
    }

    /// Fetches the host overview, container metadata and live metrics
    /// concurrently and merges metadata with stats by container id. Tolerates a
    /// missing `/system` or `/stats` (returns containers without the live fields)
    /// so a partial outage still yields a useful dashboard; only a failing
    /// `/containers` (the core list) propagates.
    public func dashboard() async throws -> StatainerDashboard {
        async let systemTask = system()
        async let containersTask = containers()
        async let statsTask = stats()

        let containers = try await containersTask
        let stats = (try? await statsTask) ?? []
        let system = try? await systemTask

        let statsByID = Dictionary(stats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let merged = containers.map { container -> StatainerContainer in
            guard let s = statsByID[container.id] else { return container }
            return container.merging(stats: s)
        }
        return StatainerDashboard(system: system, containers: merged)
    }

    // MARK: - Actions

    /// Performs a lifecycle action on a container. Throws (surfacing the server's
    /// message) when the API reports failure — e.g. an update returning `409`.
    @discardableResult
    public func perform(_ action: StatainerContainerAction, on id: String) async throws -> StatainerActionResult {
        let segment = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let endpoint = Endpoint(path: "api/v1/containers/\(segment)/\(action.rawValue)", method: .post)
        let result: StatainerActionResult = try await api.send(endpoint)
        if result.ok == false {
            throw APIError.server(statusCode: 409, body: result.message ?? "Action failed")
        }
        return result
    }

    @discardableResult public func start(_ id: String) async throws -> StatainerActionResult { try await perform(.start, on: id) }
    @discardableResult public func stop(_ id: String) async throws -> StatainerActionResult { try await perform(.stop, on: id) }
    @discardableResult public func restart(_ id: String) async throws -> StatainerActionResult { try await perform(.restart, on: id) }
    @discardableResult public func update(_ id: String) async throws -> StatainerActionResult { try await perform(.update, on: id) }
}
