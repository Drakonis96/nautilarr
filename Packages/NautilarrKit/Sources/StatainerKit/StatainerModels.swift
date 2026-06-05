import Foundation

// Models mirror the Statainer external API (`/api/v1`, Bearer / X-API-Key).
// Reference (public, official): https://github.com/Drakonis96/statainer/blob/main/API.md

/// A flag the API expresses inconsistently across versions: older builds emit an
/// integer (`0`/`1`), newer ones a JSON boolean (`true`/`false`); it may also be
/// `null`. This wrapper decodes any of those shapes so a single odd value can't
/// abort decoding of the whole container list.
public struct StatainerFlag: Codable, Sendable, Equatable, Hashable {
    public var value: Bool
    public init(_ value: Bool) { self.value = value }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { value = b }
        else if let i = try? c.decode(Int.self) { value = i != 0 }
        else if let d = try? c.decode(Double.self) { value = d != 0 }
        else if let s = try? c.decode(String.self) { value = (s as NSString).boolValue || s == "1" }
        else { value = false }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

// MARK: - System

/// Host + Docker overview from `GET /api/v1/system`.
public struct StatainerSystem: Codable, Sendable, Equatable {
    public var cpuCores: Int?
    public var maxCpuPercent: Int?
    public var cpuCountDocker: Int?
    public var memoryTotalBytes: Int64?
    public var memoryTotalMB: Double?
    public var memoryTotalGB: Double?
    public var containers: Int?
    public var containersRunning: Int?
    public var containersPaused: Int?
    public var containersStopped: Int?
    public var images: Int?
    public var dockerVersion: String?
    public var operatingSystem: String?
    public var osType: String?
    public var architecture: String?
    public var kernelVersion: String?
    public var hostname: String?
    public var appVersion: String?

    enum CodingKeys: String, CodingKey {
        case cpuCores = "cpu_cores"
        case maxCpuPercent = "max_cpu_percent"
        case cpuCountDocker = "cpu_count_docker"
        case memoryTotalBytes = "memory_total_bytes"
        case memoryTotalMB = "memory_total_mb"
        case memoryTotalGB = "memory_total_gb"
        case containers
        case containersRunning = "containers_running"
        case containersPaused = "containers_paused"
        case containersStopped = "containers_stopped"
        case images
        case dockerVersion = "docker_version"
        case operatingSystem = "operating_system"
        case osType = "os_type"
        case architecture
        case kernelVersion = "kernel_version"
        case hostname
        case appVersion = "app_version"
    }
}

// MARK: - Container

/// A Docker container as reported by `GET /api/v1/containers` (metadata) and/or
/// `GET /api/v1/stats` (live metrics). The two endpoints share an id/name/status
/// and expose complementary fields, so one struct decodes both — every field
/// beyond `id`/`name` is optional and the dashboard merges a metadata row with
/// its matching stats row by id.
public struct StatainerContainer: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var status: String?

    // Metadata (`/containers`).
    public var image: String?
    public var ports: String?
    public var uptime: String?

    // Shared.
    public var restarts: Int?
    public var uptimeSec: Int?
    public var updateAvailable: StatainerFlag?
    public var composeProject: String?
    public var composeService: String?

    // Live metrics (`/stats`).
    public var cpu: Double?
    public var mem: Double?
    public var memUsage: Double?
    public var memLimit: Double?
    public var netIoRx: Double?
    public var netIoTx: Double?
    public var blockIoR: Double?
    public var blockIoW: Double?
    public var pidCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, status, image, ports, uptime, restarts
        case uptimeSec = "uptime_sec"
        case updateAvailable = "update_available"
        case composeProject = "compose_project"
        case composeService = "compose_service"
        case cpu, mem
        case memUsage = "mem_usage"
        case memLimit = "mem_limit"
        case netIoRx = "net_io_rx"
        case netIoTx = "net_io_tx"
        case blockIoR = "block_io_r"
        case blockIoW = "block_io_w"
        case pidCount = "pid_count"
    }

    // MARK: Derived state

    /// Normalised run state, robust to casing differences across Docker versions.
    public enum State: String, Sendable {
        case running, paused, restarting, exited, created, dead, unknown
    }

    public var state: State {
        State(rawValue: (status ?? "").lowercased()) ?? .unknown
    }

    public var isRunning: Bool { state == .running || state == .restarting }
    public var isPaused: Bool { state == .paused }
    /// Whether a newer image is available for this container.
    public var hasUpdate: Bool { updateAvailable?.value ?? false }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? id : trimmed
    }

    /// Memory usage as a byte count (the API reports usage/limit in MB).
    public var memoryUsageBytes: Int64? { memUsage.map { Int64($0 * 1_048_576) } }
    public var memoryLimitBytes: Int64? { memLimit.map { Int64($0 * 1_048_576) } }

    /// Returns a copy with this (metadata) row's live-metric fields filled in from
    /// a matching `/stats` row, preferring already-present metadata values.
    public func merging(stats s: StatainerContainer) -> StatainerContainer {
        var c = self
        c.cpu = c.cpu ?? s.cpu
        c.mem = c.mem ?? s.mem
        c.memUsage = c.memUsage ?? s.memUsage
        c.memLimit = c.memLimit ?? s.memLimit
        c.netIoRx = c.netIoRx ?? s.netIoRx
        c.netIoTx = c.netIoTx ?? s.netIoTx
        c.blockIoR = c.blockIoR ?? s.blockIoR
        c.blockIoW = c.blockIoW ?? s.blockIoW
        c.pidCount = c.pidCount ?? s.pidCount
        c.status = c.status ?? s.status
        c.uptimeSec = c.uptimeSec ?? s.uptimeSec
        c.restarts = c.restarts ?? s.restarts
        c.updateAvailable = c.updateAvailable ?? s.updateAvailable
        c.composeProject = c.composeProject ?? s.composeProject
        c.composeService = c.composeService ?? s.composeService
        return c
    }
}

/// Envelope returned by `GET /api/v1/containers`.
struct StatainerContainerList: Decodable, Sendable {
    var count: Int?
    var running: Int?
    var exited: Int?
    var containers: [StatainerContainer]
}

/// Envelope returned by `GET /api/v1/stats`.
struct StatainerStatsList: Decodable, Sendable {
    var count: Int?
    var containers: [StatainerContainer]
}

// MARK: - Actions

/// The lifecycle actions Statainer exposes per container.
public enum StatainerContainerAction: String, Sendable, CaseIterable {
    case start, stop, restart, update
}

/// Response body for the POST action endpoints.
public struct StatainerActionResult: Codable, Sendable, Equatable {
    public var ok: Bool?
    public var action: String?
    public var containerID: String?
    public var name: String?
    public var message: String?

    enum CodingKeys: String, CodingKey {
        case ok, action, name, message
        case containerID = "container_id"
    }
}

/// Response body for `GET /api/v1/ping` (liveness + version).
public struct StatainerPing: Codable, Sendable, Equatable {
    public var ok: Bool?
    public var pong: Bool?
    public var version: String?
}

/// A complete dashboard snapshot: the host overview plus the merged container list.
public struct StatainerDashboard: Sendable, Equatable {
    public var system: StatainerSystem?
    public var containers: [StatainerContainer]

    public init(system: StatainerSystem?, containers: [StatainerContainer]) {
        self.system = system
        self.containers = containers
    }

    public var updatesAvailable: Int { containers.filter(\.hasUpdate).count }
    public var runningCount: Int { containers.filter(\.isRunning).count }
}
