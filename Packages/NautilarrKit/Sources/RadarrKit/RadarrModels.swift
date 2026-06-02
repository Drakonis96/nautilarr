import Foundation

// MARK: - System & health

/// `GET /api/v3/system/status`.
public struct RadarrSystemStatus: Codable, Sendable, Equatable {
    public var version: String?
    public var appName: String?
    public var instanceName: String?
    public var osName: String?
    public var isProduction: Bool?
}

/// `GET /api/v3/health`.
public struct RadarrHealthItem: Codable, Sendable, Equatable, Identifiable {
    public var id: Int { (source?.hashValue ?? 0) ^ (message?.hashValue ?? 0) }
    public var source: String?
    public var type: String?
    public var message: String?
    public var wikiUrl: String?

    public enum Severity: String, Sendable { case ok, notice, warning, error, unknown }
    public var severity: Severity { Severity(rawValue: type?.lowercased() ?? "") ?? .unknown }
}

// MARK: - Quality

public struct RadarrQuality: Codable, Sendable, Equatable, Hashable {
    public var id: Int?
    public var name: String?
    public var resolution: Int?
}

public struct RadarrQualityModel: Codable, Sendable, Equatable, Hashable {
    public var quality: RadarrQuality?
    public var displayName: String { quality?.name ?? "Unknown" }
}

public struct RadarrQualityProfile: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var name: String
}

public struct RadarrRootFolder: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var path: String
    public var accessible: Bool?
    public var freeSpace: Int64?
}

// MARK: - Images

public struct RadarrImage: Codable, Sendable, Equatable, Hashable {
    public var coverType: String?
    public var url: String?
    public var remoteUrl: String?
}

// MARK: - File / media info

/// A language tag on a file (`{ id, name }`).
public struct RadarrLanguage: Codable, Sendable, Equatable, Hashable {
    public var id: Int?
    public var name: String?
}

/// Technical media details of a downloaded file (`movieFile.mediaInfo`).
/// VERIFY: field names against the running Radarr version.
public struct RadarrMediaInfo: Codable, Sendable, Equatable, Hashable {
    public var videoCodec: String?
    public var videoDynamicRange: String?
    public var videoDynamicRangeType: String?
    public var resolution: String?          // e.g. "1920x1080"
    public var runTime: String?
    public var videoFps: Double?
    public var audioCodec: String?
    public var audioChannels: Double?
    public var audioLanguages: String?
    public var subtitles: String?
}

/// The downloaded file linked to a movie (`movie.movieFile`).
public struct RadarrMovieFile: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var relativePath: String?
    public var size: Int64?
    public var dateAdded: Date?
    public var quality: RadarrQualityModel?
    public var mediaInfo: RadarrMediaInfo?
    public var languages: [RadarrLanguage]?
}

// MARK: - Ratings

public struct RadarrRating: Codable, Sendable, Equatable, Hashable {
    public var votes: Int?
    public var value: Double?
}

/// Movie ratings from the various providers Radarr aggregates.
public struct RadarrRatings: Codable, Sendable, Equatable, Hashable {
    public var imdb: RadarrRating?
    public var tmdb: RadarrRating?
    public var metacritic: RadarrRating?
    public var rottenTomatoes: RadarrRating?
}

// MARK: - Movie

/// A movie resource (`GET /api/v3/movie`). Fields are optional to tolerate
/// version differences and unknown extras.
public struct RadarrMovie: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var title: String
    public var originalTitle: String?
    public var sortTitle: String?
    public var overview: String?
    /// `announced`, `inCinemas`, `released`, `deleted`.
    public var status: String?
    public var year: Int?
    public var runtime: Int?
    public var monitored: Bool?
    public var hasFile: Bool?
    public var path: String?
    public var qualityProfileId: Int?
    public var tmdbId: Int?
    public var imdbId: String?
    public var titleSlug: String?
    public var certification: String?
    public var studio: String?
    public var genres: [String]?
    public var tags: [Int]?
    public var added: Date?
    public var sizeOnDisk: Int64?
    public var inCinemas: Date?
    public var physicalRelease: Date?
    public var digitalRelease: Date?
    /// `announced`, `inCinemas`, `released`.
    public var minimumAvailability: String?
    public var isAvailable: Bool?
    public var images: [RadarrImage]?
    public var ratings: RadarrRatings?
    /// The downloaded file (present when `hasFile`), with technical media info.
    public var movieFile: RadarrMovieFile?

    public func imageURL(coverType: String = "poster") -> String? {
        let match = images?.first { $0.coverType?.lowercased() == coverType.lowercased() }
        return match?.remoteUrl ?? match?.url
    }
}

// MARK: - Add movie

public struct RadarrAddOptions: Codable, Sendable, Equatable {
    public var searchForMovie: Bool?
    public var monitor: String?

    public init(searchForMovie: Bool? = true, monitor: String? = "movieOnly") {
        self.searchForMovie = searchForMovie
        self.monitor = monitor
    }
}

/// Payload to add a movie.
///
/// VERIFY: Radarr expects the lookup resource echoed back with
/// `qualityProfileId`, `rootFolderPath`, `monitored`, `minimumAvailability` and
/// `addOptions`. Confirm the exact required set against the running version.
public struct RadarrAddMovieRequest: Codable, Sendable {
    public var title: String
    public var tmdbId: Int?
    public var titleSlug: String?
    public var year: Int?
    public var qualityProfileId: Int
    public var rootFolderPath: String
    public var monitored: Bool
    public var minimumAvailability: String
    public var images: [RadarrImage]?
    public var addOptions: RadarrAddOptions

    public init(
        lookup: RadarrMovie,
        qualityProfileId: Int,
        rootFolderPath: String,
        monitored: Bool = true,
        minimumAvailability: String = "released",
        addOptions: RadarrAddOptions = RadarrAddOptions()
    ) {
        self.title = lookup.title
        self.tmdbId = lookup.tmdbId
        self.titleSlug = lookup.titleSlug
        self.year = lookup.year
        self.qualityProfileId = qualityProfileId
        self.rootFolderPath = rootFolderPath
        self.monitored = monitored
        self.minimumAvailability = minimumAvailability
        self.images = lookup.images
        self.addOptions = addOptions
    }
}

// MARK: - Paged envelope, queue

public struct RadarrPaged<Record: Codable & Sendable>: Codable, Sendable {
    public var page: Int?
    public var pageSize: Int?
    public var totalRecords: Int?
    public var records: [Record]
}

public struct RadarrQueueItem: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var movieId: Int?
    public var title: String?
    public var status: String?
    public var trackedDownloadStatus: String?
    public var trackedDownloadState: String?
    public var size: Double?
    public var sizeleft: Double?
    public var timeleft: String?
    public var downloadClient: String?
    public var protocolName: String?
    public var indexer: String?
    public var quality: RadarrQualityModel?
    public var errorMessage: String?
    public var movie: RadarrMovie?

    private enum CodingKeys: String, CodingKey {
        case id, movieId, title, status, trackedDownloadStatus, trackedDownloadState
        case size, sizeleft, timeleft, downloadClient, indexer, quality, errorMessage, movie
        case protocolName = "protocol"
    }

    public var progress: Double {
        guard let size, size > 0, let sizeleft else { return 0 }
        return max(0, min(1, (size - sizeleft) / size))
    }
}

public typealias RadarrQueue = RadarrPaged<RadarrQueueItem>

// MARK: - Releases

public struct RadarrRelease: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { guid ?? title ?? UUID().uuidString }
    public var guid: String?
    public var title: String?
    public var indexer: String?
    public var indexerId: Int?
    public var size: Int64?
    public var seeders: Int?
    public var leechers: Int?
    public var quality: RadarrQualityModel?
    public var protocolName: String?
    public var approved: Bool?
    public var rejected: Bool?
    public var rejections: [String]?

    private enum CodingKeys: String, CodingKey {
        case guid, title, indexer, indexerId, size, seeders, leechers, quality
        case approved, rejected, rejections
        case protocolName = "protocol"
    }
}

public struct RadarrGrabReleaseRequest: Codable, Sendable {
    public var guid: String
    public var indexerId: Int
    public init(guid: String, indexerId: Int) { self.guid = guid; self.indexerId = indexerId }
}

// MARK: - Commands

/// Body for `POST /api/v3/command`.
///
/// VERIFY: command names — `MoviesSearch` (with `movieIds`) and `RefreshMovie`
/// are used here; confirm against the running Radarr version.
public struct RadarrCommandRequest: Encodable, Sendable {
    public var name: String
    public var movieIds: [Int]?

    public init(name: String, movieIds: [Int]? = nil) {
        self.name = name
        self.movieIds = movieIds
    }

    public static func movieSearch(movieId: Int) -> RadarrCommandRequest {
        RadarrCommandRequest(name: "MoviesSearch", movieIds: [movieId])
    }
    public static func refreshMovie(movieId: Int) -> RadarrCommandRequest {
        RadarrCommandRequest(name: "RefreshMovie", movieIds: [movieId])
    }
}

public struct RadarrCommandResource: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String?
    public var status: String?
}

// MARK: - Editing

/// Body for `PUT /api/v3/movie/editor` — bulk-edits one or more movies. Only the
/// present fields are changed, so this serves both single- and multi-item edits.
///
/// VERIFY: field names `movieIds`, `monitored`, `qualityProfileId`,
/// `rootFolderPath`, `moveFiles` against the running Radarr version.
public struct RadarrMovieEditorRequest: Encodable, Sendable {
    public var movieIds: [Int]
    public var monitored: Bool?
    public var qualityProfileId: Int?
    public var rootFolderPath: String?
    public var moveFiles: Bool?

    public init(
        movieIds: [Int],
        monitored: Bool? = nil,
        qualityProfileId: Int? = nil,
        rootFolderPath: String? = nil,
        moveFiles: Bool? = nil
    ) {
        self.movieIds = movieIds
        self.monitored = monitored
        self.qualityProfileId = qualityProfileId
        self.rootFolderPath = rootFolderPath
        self.moveFiles = moveFiles
    }
}
