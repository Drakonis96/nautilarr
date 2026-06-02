import Foundation

// MARK: - System status

/// `GET /api/v3/system/status` — used for the connection test and to display
/// the server version.
public struct SonarrSystemStatus: Codable, Sendable, Equatable {
    public var version: String?
    public var appName: String?
    public var instanceName: String?
    public var buildTime: Date?
    public var osName: String?
    public var isProduction: Bool?
    public var runtimeName: String?
}

// MARK: - Health

/// `GET /api/v3/health` — health check messages shown in the dashboard.
public struct SonarrHealthItem: Codable, Sendable, Equatable, Identifiable {
    public var id: Int { (source?.hashValue ?? 0) ^ (message?.hashValue ?? 0) }

    public var source: String?
    /// One of `ok`, `notice`, `warning`, `error`.
    public var type: String?
    public var message: String?
    public var wikiUrl: String?

    public enum Severity: String, Sendable {
        case ok, notice, warning, error, unknown
    }

    public var severity: Severity {
        Severity(rawValue: type?.lowercased() ?? "") ?? .unknown
    }
}
