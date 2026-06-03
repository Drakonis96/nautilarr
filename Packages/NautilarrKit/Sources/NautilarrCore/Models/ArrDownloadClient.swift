import Foundation

/// A download client configured **inside** a Sonarr/Radarr instance (their
/// Settings → Download Clients), as returned by `GET /api/v3/downloadclient`.
///
/// Intentionally minimal — just the fields needed to list and toggle a client.
/// Writes use a raw-dictionary round-trip in the kit clients so the full server
/// resource is preserved (this model never has to map every field).
public struct ArrDownloadClient: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var name: String?
    public var enable: Bool?
    public var priority: Int?
    /// The client implementation, e.g. "QBittorrent", "Sabnzbd".
    public var implementation: String?
    /// `usenet` or `torrent`.
    public var protocolName: String?

    public init(id: Int, name: String? = nil, enable: Bool? = nil, priority: Int? = nil,
                implementation: String? = nil, protocolName: String? = nil) {
        self.id = id
        self.name = name
        self.enable = enable
        self.priority = priority
        self.implementation = implementation
        self.protocolName = protocolName
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, enable, priority, implementation
        case protocolName = "protocol"
    }
}
