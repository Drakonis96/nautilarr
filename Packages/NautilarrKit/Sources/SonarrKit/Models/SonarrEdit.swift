import Foundation

/// Body for `PUT /api/v3/series/editor` — bulk-edits one or more series. The
/// server only changes the fields that are present, so the same endpoint serves
/// single-item edits (monitored toggle, quality-profile change) and multi-item
/// edits. `seriesIds` is always sent; everything else is omitted when nil.
///
/// VERIFY: field names `seriesIds`, `monitored`, `qualityProfileId`,
/// `rootFolderPath`, `moveFiles` against the running Sonarr version.
public struct SonarrSeriesEditorRequest: Encodable, Sendable {
    public var seriesIds: [Int]
    public var monitored: Bool?
    public var qualityProfileId: Int?
    public var rootFolderPath: String?
    public var moveFiles: Bool?

    public init(
        seriesIds: [Int],
        monitored: Bool? = nil,
        qualityProfileId: Int? = nil,
        rootFolderPath: String? = nil,
        moveFiles: Bool? = nil
    ) {
        self.seriesIds = seriesIds
        self.monitored = monitored
        self.qualityProfileId = qualityProfileId
        self.rootFolderPath = rootFolderPath
        self.moveFiles = moveFiles
    }
}

/// Body for `PUT /api/v3/episode/monitor` — toggles monitoring on individual
/// episodes.
///
/// VERIFY: `{ "episodeIds": [...], "monitored": Bool }`.
public struct SonarrEpisodeMonitorRequest: Encodable, Sendable {
    public var episodeIds: [Int]
    public var monitored: Bool

    public init(episodeIds: [Int], monitored: Bool) {
        self.episodeIds = episodeIds
        self.monitored = monitored
    }
}
