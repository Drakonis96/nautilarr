import Foundation
import NautilarrCore

// MARK: - Models

/// A download group (queue item) from NZBGet's `listgroups`.
public struct NZBGetGroup: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int { nzbID }
    public var nzbID: Int
    public var nzbName: String?
    /// `QUEUED`, `DOWNLOADING`, `PAUSED`, `POSTPROCESSING`, …
    public var status: String?
    public var fileSizeMB: Int?
    public var remainingSizeMB: Int?
    public var category: String?

    private enum CodingKeys: String, CodingKey {
        case nzbID = "NZBID"
        case nzbName = "NZBName"
        case status = "Status"
        case fileSizeMB = "FileSizeMB"
        case remainingSizeMB = "RemainingSizeMB"
        case category = "Category"
    }

    public var progress: Double {
        guard let total = fileSizeMB, total > 0, let left = remainingSizeMB else { return 0 }
        return max(0, min(1, Double(total - left) / Double(total)))
    }
    public var isPaused: Bool { status?.uppercased().contains("PAUSED") ?? false }
    public var sizeBytes: Double? { fileSizeMB.map { Double($0) * 1_048_576 } }
}

/// Global status from NZBGet's `status`.
public struct NZBGetStatus: Codable, Sendable, Equatable {
    public var downloadRate: Int?
    public var remainingSizeMB: Int?
    public var downloadPaused: Bool?

    private enum CodingKeys: String, CodingKey {
        case downloadRate = "DownloadRate"
        case remainingSizeMB = "RemainingSizeMB"
        case downloadPaused = "DownloadPaused"
    }
}

/// JSON-RPC response envelope: `{ "version": …, "result": <T>, "id": 1 }`.
private struct NZBRPCResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let result: T
}

// MARK: - Client

/// Client for the NZBGet JSON-RPC API. Authentication is HTTP Basic
/// (username/password), attached by `BasicAuthorizer` via `ServiceClientFactory`.
///
/// API reference (public, official): https://nzbget.com/documentation/api/
public struct NZBGetClient: Sendable {
    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public init(instance: ServiceInstance, credential: Credential, monitor: NetworkMonitor? = nil) {
        self.api = ServiceClientFactory.makeClient(for: instance, credential: credential, monitor: monitor)
    }

    /// Performs a JSON-RPC call and returns the decoded `result`.
    private func call<T: Decodable & Sendable>(_ method: String, params: [Any] = [], as type: T.Type = T.self) async throws -> T {
        let endpoint = try Endpoint.jsonObject("jsonrpc", object: ["method": method, "params": params, "id": 1])
        let response: NZBRPCResponse<T> = try await api.send(endpoint)
        return response.result
    }

    // MARK: Connection test
    public func version() async throws -> String { try await call("version") }

    // MARK: Queue & status
    public func groups() async throws -> [NZBGetGroup] { try await call("listgroups", params: [0]) }
    public func status() async throws -> NZBGetStatus { try await call("status") }

    // MARK: Global controls
    @discardableResult public func pauseAll() async throws -> Bool { try await call("pausedownload") }
    @discardableResult public func resumeAll() async throws -> Bool { try await call("resumedownload") }
    /// Sets the global speed limit in KB/s (`0` = unlimited).
    @discardableResult public func setRate(kbps: Int) async throws -> Bool { try await call("rate", params: [kbps]) }

    // MARK: Per-group controls (via editqueue)
    @discardableResult public func pauseGroup(id: Int) async throws -> Bool { try await edit("GroupPause", id: id) }
    @discardableResult public func resumeGroup(id: Int) async throws -> Bool { try await edit("GroupResume", id: id) }
    @discardableResult public func deleteGroup(id: Int, deleteFiles: Bool = true) async throws -> Bool {
        try await edit(deleteFiles ? "GroupFinalDelete" : "GroupDelete", id: id)
    }

    private func edit(_ command: String, id: Int) async throws -> Bool {
        // editqueue(Command, Offset, Text, IDs)
        try await call("editqueue", params: [command, 0, "", [id]])
    }
}
