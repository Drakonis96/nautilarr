import Foundation

/// A release returned by interactive search (`GET /api/v3/release?episodeId=…`).
public struct SonarrRelease: Codable, Sendable, Equatable, Hashable, Identifiable {
    /// `guid` uniquely identifies a release within an indexer.
    public var id: String { guid ?? title ?? UUID().uuidString }

    public var guid: String?
    public var title: String?
    public var indexer: String?
    public var indexerId: Int?
    public var size: Int64?
    public var seeders: Int?
    public var leechers: Int?
    public var age: Int?
    public var ageHours: Double?
    public var quality: SonarrQualityModel?
    public var protocolName: String?
    public var approved: Bool?
    public var rejected: Bool?
    public var rejections: [String]?
    public var downloadUrl: String?
    public var infoUrl: String?

    private enum CodingKeys: String, CodingKey {
        case guid, title, indexer, indexerId, size, seeders, leechers
        case age, ageHours, quality, approved, rejected, rejections
        case downloadUrl, infoUrl
        case protocolName = "protocol"
    }
}

/// Body to push a chosen release for download (`POST /api/v3/release`).
public struct SonarrGrabReleaseRequest: Codable, Sendable {
    public var guid: String
    public var indexerId: Int

    public init(guid: String, indexerId: Int) {
        self.guid = guid
        self.indexerId = indexerId
    }
}
