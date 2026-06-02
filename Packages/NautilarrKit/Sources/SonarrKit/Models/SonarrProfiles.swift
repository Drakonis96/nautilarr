import Foundation

// MARK: - Quality model (shared by episode files, queue and releases)

public struct SonarrQuality: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int?
    public var name: String?
    public var resolution: Int?
    public var source: String?
}

public struct SonarrQualityRevision: Codable, Sendable, Equatable, Hashable {
    public var version: Int?
    public var real: Int?
    public var isRepack: Bool?
}

public struct SonarrQualityModel: Codable, Sendable, Equatable, Hashable {
    public var quality: SonarrQuality?
    public var revision: SonarrQualityRevision?

    public var displayName: String { quality?.name ?? "Unknown" }
}

// MARK: - Quality profile

public struct SonarrQualityProfile: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var upgradeAllowed: Bool?
}

// MARK: - Language profile (Sonarr v3 only)

public struct SonarrLanguageProfile: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var name: String
}

// MARK: - Root folder

public struct SonarrRootFolder: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var path: String
    public var accessible: Bool?
    public var freeSpace: Int64?
}
