import Foundation

/// A language tag on a file (`{ id, name }`).
public struct SonarrLanguage: Codable, Sendable, Equatable, Hashable {
    public var id: Int?
    public var name: String?
}

/// Technical media details of a downloaded file (`episodeFile.mediaInfo`).
/// VERIFY: field names against the running Sonarr version.
public struct SonarrMediaInfo: Codable, Sendable, Equatable, Hashable {
    public var videoCodec: String?
    public var videoDynamicRange: String?
    public var resolution: String?          // e.g. "1920x1080"
    public var runTime: String?
    public var videoFps: Double?
    public var audioCodec: String?
    public var audioChannels: Double?
    public var audioLanguages: String?
    public var subtitles: String?
}

/// Episode-file info referenced by an episode (when `includeEpisodeFile=true`).
public struct SonarrEpisodeFile: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var relativePath: String?
    public var size: Int64?
    public var quality: SonarrQualityModel?
    public var dateAdded: Date?
    public var mediaInfo: SonarrMediaInfo?
    public var languages: [SonarrLanguage]?
}

/// `GET /api/v3/episode?seriesId={id}` and the calendar endpoint.
public struct SonarrEpisode: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var seriesId: Int?
    public var tvdbId: Int?
    public var episodeFileId: Int?
    public var seasonNumber: Int?
    public var episodeNumber: Int?
    public var title: String?
    public var airDate: Date?
    public var airDateUtc: Date?
    public var overview: String?
    public var hasFile: Bool?
    public var monitored: Bool?
    public var runtime: Int?
    public var absoluteEpisodeNumber: Int?
    public var episodeFile: SonarrEpisodeFile?
    /// Present on calendar/queue responses when `includeSeries=true`.
    public var series: SonarrSeries?

    /// Standard `SxxEyy` label.
    public var seasonEpisodeCode: String {
        let s = seasonNumber.map { String(format: "S%02d", $0) } ?? "S??"
        let e = episodeNumber.map { String(format: "E%02d", $0) } ?? "E??"
        return s + e
    }
}
