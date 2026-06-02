import Foundation
import NautilarrCore

// MARK: - Models (mirror the Unraid GraphQL schema)

public struct UnraidOS: Codable, Sendable, Equatable {
    public var platform: String?
    public var distro: String?
    public var release: String?
    public var uptime: String?
}

public struct UnraidCPU: Codable, Sendable, Equatable {
    public var manufacturer: String?
    public var brand: String?
    public var cores: Int?
    public var threads: Int?
}

public struct UnraidInfo: Codable, Sendable, Equatable {
    public var os: UnraidOS?
    public var cpu: UnraidCPU?
}

public struct UnraidDiskCapacity: Codable, Sendable, Equatable {
    public var free: String?
    public var used: String?
    public var total: String?
}

public struct UnraidArrayCapacity: Codable, Sendable, Equatable {
    public var disks: UnraidDiskCapacity?
}

public struct UnraidArray: Codable, Sendable, Equatable {
    public var state: String?
    public var capacity: UnraidArrayCapacity?
}

public struct UnraidDockerContainer: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var names: [String]?
    public var state: String?
    public var status: String?
    public var autoStart: Bool?

    public var displayName: String { names?.first?.replacingOccurrences(of: "/", with: "") ?? id }
    public var isRunning: Bool { state?.uppercased() == "RUNNING" }
}

public struct UnraidSnapshot: Codable, Sendable, Equatable {
    public var info: UnraidInfo?
    public var array: UnraidArray?
    public var dockerContainers: [UnraidDockerContainer]?

    public var runningContainers: Int { dockerContainers?.filter { $0.isRunning }.count ?? 0 }
    public var totalContainers: Int { dockerContainers?.count ?? 0 }
}

/// GraphQL envelope.
private struct GraphQLResponse<T: Decodable & Sendable>: Decodable, Sendable {
    struct GraphQLError: Decodable, Sendable { let message: String? }
    let data: T?
    let errors: [GraphQLError]?
}

// MARK: - Client

/// Client for the official Unraid GraphQL API (`/graphql`, `x-api-key` header).
/// Provides system info, array status and Docker containers — no SSH required.
///
/// API reference (public, official): https://docs.unraid.net/API/
public struct UnraidClient: Sendable {
    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public init(instance: ServiceInstance, credential: Credential, monitor: NetworkMonitor? = nil) {
        self.api = ServiceClientFactory.makeClient(for: instance, credential: credential, monitor: monitor)
    }

    /// Verified field set from the Unraid API docs.
    private static let snapshotQuery = """
    query { \
    info { os { platform distro release uptime } cpu { manufacturer brand cores threads } } \
    array { state capacity { disks { free used total } } } \
    dockerContainers { id names state status autoStart } \
    }
    """

    private func query<T: Decodable & Sendable>(_ query: String, as type: T.Type) async throws -> T {
        let endpoint = try Endpoint.jsonObject("graphql", object: ["query": query])
        let response: GraphQLResponse<T> = try await api.send(endpoint)
        if let message = response.errors?.compactMap(\.message).first {
            throw APIError.server(statusCode: 200, body: message)
        }
        guard let data = response.data else { throw APIError.invalidResponse }
        return data
    }

    /// Connection test + full dashboard snapshot.
    public func snapshot() async throws -> UnraidSnapshot {
        try await query(Self.snapshotQuery, as: UnraidSnapshot.self)
    }
}
