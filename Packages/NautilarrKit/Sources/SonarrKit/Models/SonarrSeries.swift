import Foundation

// MARK: - Images

public struct SonarrImage: Codable, Sendable, Equatable, Hashable {
    /// `poster`, `banner`, `fanart`, `clearlogo`, …
    public var coverType: String?
    /// Local, server-relative URL (e.g. `/MediaCover/12/poster.jpg`).
    public var url: String?
    /// Absolute URL on the metadata provider's CDN (usually public).
    public var remoteUrl: String?
}

// MARK: - Season & statistics

public struct SonarrSeasonStatistics: Codable, Sendable, Equatable, Hashable {
    public var episodeFileCount: Int?
    public var episodeCount: Int?
    public var totalEpisodeCount: Int?
    public var sizeOnDisk: Int64?
    public var percentOfEpisodes: Double?
}

public struct SonarrSeason: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int { seasonNumber }
    public var seasonNumber: Int
    public var monitored: Bool?
    public var statistics: SonarrSeasonStatistics?
}

public struct SonarrSeriesStatistics: Codable, Sendable, Equatable, Hashable {
    public var seasonCount: Int?
    public var episodeFileCount: Int?
    public var episodeCount: Int?
    public var totalEpisodeCount: Int?
    public var sizeOnDisk: Int64?
    public var percentOfEpisodes: Double?
}

public struct SonarrRatings: Codable, Sendable, Equatable, Hashable {
    public var votes: Int?
    public var value: Double?
}

// MARK: - Series

/// A TV series resource. Fields are mostly optional to tolerate differences
/// between Sonarr v3 and v4 (e.g. `languageProfileId` exists in v3 but not v4)
/// and to survive unknown/added fields gracefully.
public struct SonarrSeries: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var title: String
    public var sortTitle: String?
    public var overview: String?
    /// `continuing`, `ended`, `upcoming`, `deleted`.
    public var status: String?
    public var network: String?
    public var airTime: String?
    public var year: Int?
    public var runtime: Int?
    public var monitored: Bool?
    public var seasonFolder: Bool?
    public var path: String?
    public var qualityProfileId: Int?
    // VERIFY: present in Sonarr v3, removed in v4 — kept optional for both.
    public var languageProfileId: Int?
    public var seriesType: String?
    public var tvdbId: Int?
    public var tmdbId: Int?
    public var imdbId: String?
    public var titleSlug: String?
    public var certification: String?
    public var genres: [String]?
    public var tags: [Int]?
    public var added: Date?
    public var ratings: SonarrRatings?
    public var images: [SonarrImage]?
    public var seasons: [SonarrSeason]?
    public var statistics: SonarrSeriesStatistics?
    public var ended: Bool?

    /// Best image URL for a given cover type, preferring the public remote CDN.
    public func imageURL(coverType: String = "poster") -> String? {
        let match = images?.first { $0.coverType?.lowercased() == coverType.lowercased() }
        return match?.remoteUrl ?? match?.url
    }
}

// MARK: - Add series

/// Options included when adding a series, controlling the initial search.
public struct SonarrAddOptions: Codable, Sendable, Equatable {
    public var ignoreEpisodesWithFiles: Bool?
    public var ignoreEpisodesWithoutFiles: Bool?
    /// Trigger an automatic search for missing episodes right after adding.
    public var searchForMissingEpisodes: Bool?
    public var monitor: String?

    public init(
        ignoreEpisodesWithFiles: Bool? = false,
        ignoreEpisodesWithoutFiles: Bool? = false,
        searchForMissingEpisodes: Bool? = true,
        monitor: String? = "all"
    ) {
        self.ignoreEpisodesWithFiles = ignoreEpisodesWithFiles
        self.ignoreEpisodesWithoutFiles = ignoreEpisodesWithoutFiles
        self.searchForMissingEpisodes = searchForMissingEpisodes
        self.monitor = monitor
    }
}

/// The payload used to add a series. Built from a lookup result plus the user's
/// chosen quality profile, root folder and monitoring options.
///
/// VERIFY: Sonarr expects the full series resource echoed back from
/// `/series/lookup` with `qualityProfileId`, `rootFolderPath`, `monitored`,
/// `seasonFolder` and `addOptions` set. This struct carries the commonly
/// required fields; confirm the exact required set against the running version.
public struct SonarrAddSeriesRequest: Codable, Sendable {
    public var title: String
    public var tvdbId: Int?
    public var titleSlug: String?
    public var year: Int?
    public var qualityProfileId: Int
    public var languageProfileId: Int?
    public var rootFolderPath: String
    public var monitored: Bool
    public var seasonFolder: Bool
    public var seriesType: String?
    public var seasons: [SonarrSeason]?
    public var images: [SonarrImage]?
    public var addOptions: SonarrAddOptions

    public init(
        lookup: SonarrSeries,
        qualityProfileId: Int,
        languageProfileId: Int?,
        rootFolderPath: String,
        monitored: Bool = true,
        seasonFolder: Bool = true,
        addOptions: SonarrAddOptions = SonarrAddOptions()
    ) {
        self.title = lookup.title
        self.tvdbId = lookup.tvdbId
        self.titleSlug = lookup.titleSlug
        self.year = lookup.year
        self.qualityProfileId = qualityProfileId
        self.languageProfileId = languageProfileId
        self.rootFolderPath = rootFolderPath
        self.monitored = monitored
        self.seasonFolder = seasonFolder
        self.seriesType = lookup.seriesType
        self.seasons = lookup.seasons
        self.images = lookup.images
        self.addOptions = addOptions
    }
}
