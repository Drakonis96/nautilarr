import Foundation

/// Body for `POST /api/v3/command`. The `name` selects the command; extra keys
/// are encoded dynamically because each command takes different parameters.
///
/// Examples:
/// - `{ "name": "SeriesSearch", "seriesId": 12 }`
/// - `{ "name": "EpisodeSearch", "episodeIds": [101, 102] }`
/// - `{ "name": "RefreshSeries", "seriesId": 12 }`
public struct SonarrCommandRequest: Encodable, Sendable {
    public var name: String
    public var seriesId: Int?
    public var episodeIds: [Int]?
    public var seasonNumber: Int?

    public init(name: String, seriesId: Int? = nil, episodeIds: [Int]? = nil, seasonNumber: Int? = nil) {
        self.name = name
        self.seriesId = seriesId
        self.episodeIds = episodeIds
        self.seasonNumber = seasonNumber
    }

    public static func seriesSearch(seriesId: Int) -> SonarrCommandRequest {
        SonarrCommandRequest(name: "SeriesSearch", seriesId: seriesId)
    }

    public static func episodeSearch(episodeIds: [Int]) -> SonarrCommandRequest {
        SonarrCommandRequest(name: "EpisodeSearch", episodeIds: episodeIds)
    }

    public static func seasonSearch(seriesId: Int, seasonNumber: Int) -> SonarrCommandRequest {
        SonarrCommandRequest(name: "SeasonSearch", seriesId: seriesId, seasonNumber: seasonNumber)
    }

    public static func refreshSeries(seriesId: Int) -> SonarrCommandRequest {
        SonarrCommandRequest(name: "RefreshSeries", seriesId: seriesId)
    }
}

/// Response from a queued command (`POST /api/v3/command`).
public struct SonarrCommandResource: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String?
    /// `queued`, `started`, `completed`, `failed`, …
    public var status: String?
    public var queued: Date?
    public var started: Date?
    public var ended: Date?
}
