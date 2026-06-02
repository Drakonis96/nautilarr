import Foundation

// MARK: - System & health

/// `GET /api/v1/system/status`.
public struct LidarrSystemStatus: Codable, Sendable, Equatable {
    public var version: String?
    public var appName: String?
    public var instanceName: String?
    public var osName: String?
    public var isProduction: Bool?
}

public struct LidarrHealthItem: Codable, Sendable, Equatable, Identifiable {
    public var id: Int { (source?.hashValue ?? 0) ^ (message?.hashValue ?? 0) }
    public var source: String?
    public var type: String?
    public var message: String?
    public var wikiUrl: String?

    public enum Severity: String, Sendable { case ok, notice, warning, error, unknown }
    public var severity: Severity { Severity(rawValue: type?.lowercased() ?? "") ?? .unknown }
}

// MARK: - Images & quality

public struct LidarrImage: Codable, Sendable, Equatable, Hashable {
    public var coverType: String?
    public var url: String?
    public var remoteUrl: String?
}

public struct LidarrQuality: Codable, Sendable, Equatable, Hashable {
    public var id: Int?
    public var name: String?
}
public struct LidarrQualityModel: Codable, Sendable, Equatable, Hashable {
    public var quality: LidarrQuality?
    public var displayName: String { quality?.name ?? "Unknown" }
}

public struct LidarrQualityProfile: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var name: String
}
public struct LidarrMetadataProfile: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var name: String
}
public struct LidarrRootFolder: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var path: String
    public var accessible: Bool?
    public var freeSpace: Int64?
}

// MARK: - Statistics

public struct LidarrStatistics: Codable, Sendable, Equatable, Hashable {
    public var albumCount: Int?
    public var trackFileCount: Int?
    public var trackCount: Int?
    public var totalTrackCount: Int?
    public var sizeOnDisk: Int64?
    public var percentOfTracks: Double?
}

// MARK: - Artist

public struct LidarrArtist: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var artistName: String
    public var foreignArtistId: String?
    public var overview: String?
    /// `continuing`, `ended`.
    public var status: String?
    public var monitored: Bool?
    public var path: String?
    public var qualityProfileId: Int?
    public var metadataProfileId: Int?
    public var genres: [String]?
    public var added: Date?
    public var images: [LidarrImage]?
    public var statistics: LidarrStatistics?

    public func imageURL(coverType: String = "poster") -> String? {
        let match = images?.first { $0.coverType?.lowercased() == coverType.lowercased() }
        return match?.remoteUrl ?? match?.url
    }
}

// MARK: - Album

public struct LidarrAlbum: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var title: String
    public var artistId: Int?
    public var foreignAlbumId: String?
    public var albumType: String?
    public var releaseDate: Date?
    public var monitored: Bool?
    public var images: [LidarrImage]?
    public var statistics: LidarrStatistics?
}

// MARK: - Add artist

public struct LidarrAddOptions: Codable, Sendable, Equatable {
    public var monitor: String?
    public var searchForMissingAlbums: Bool?

    public init(monitor: String? = "all", searchForMissingAlbums: Bool? = true) {
        self.monitor = monitor
        self.searchForMissingAlbums = searchForMissingAlbums
    }
}

/// Payload to add an artist.
///
/// VERIFY: Lidarr requires `foreignArtistId`, `qualityProfileId`,
/// `metadataProfileId`, `rootFolderPath`, `monitored` and `addOptions`. Confirm
/// the exact required set against the running version.
public struct LidarrAddArtistRequest: Codable, Sendable {
    public var artistName: String
    public var foreignArtistId: String?
    public var qualityProfileId: Int
    public var metadataProfileId: Int
    public var rootFolderPath: String
    public var monitored: Bool
    public var images: [LidarrImage]?
    public var addOptions: LidarrAddOptions

    public init(
        lookup: LidarrArtist,
        qualityProfileId: Int,
        metadataProfileId: Int,
        rootFolderPath: String,
        monitored: Bool = true,
        addOptions: LidarrAddOptions = LidarrAddOptions()
    ) {
        self.artistName = lookup.artistName
        self.foreignArtistId = lookup.foreignArtistId
        self.qualityProfileId = qualityProfileId
        self.metadataProfileId = metadataProfileId
        self.rootFolderPath = rootFolderPath
        self.monitored = monitored
        self.images = lookup.images
        self.addOptions = addOptions
    }
}

// MARK: - Paged envelope & queue

public struct LidarrPaged<Record: Codable & Sendable>: Codable, Sendable {
    public var page: Int?
    public var pageSize: Int?
    public var totalRecords: Int?
    public var records: [Record]
}

public struct LidarrQueueItem: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var artistId: Int?
    public var albumId: Int?
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
    public var quality: LidarrQualityModel?
    public var errorMessage: String?
    public var artist: LidarrArtist?
    public var album: LidarrAlbum?

    private enum CodingKeys: String, CodingKey {
        case id, artistId, albumId, title, status, trackedDownloadStatus, trackedDownloadState
        case size, sizeleft, timeleft, downloadClient, indexer, quality, errorMessage, artist, album
        case protocolName = "protocol"
    }

    public var progress: Double {
        guard let size, size > 0, let sizeleft else { return 0 }
        return max(0, min(1, (size - sizeleft) / size))
    }
}

public typealias LidarrQueue = LidarrPaged<LidarrQueueItem>

// MARK: - Releases

public struct LidarrRelease: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { guid ?? title ?? UUID().uuidString }
    public var guid: String?
    public var title: String?
    public var indexer: String?
    public var indexerId: Int?
    public var size: Int64?
    public var seeders: Int?
    public var leechers: Int?
    public var quality: LidarrQualityModel?
    public var protocolName: String?
    public var rejected: Bool?
    public var rejections: [String]?

    private enum CodingKeys: String, CodingKey {
        case guid, title, indexer, indexerId, size, seeders, leechers, quality, rejected, rejections
        case protocolName = "protocol"
    }
}

public struct LidarrGrabReleaseRequest: Codable, Sendable {
    public var guid: String
    public var indexerId: Int
    public init(guid: String, indexerId: Int) { self.guid = guid; self.indexerId = indexerId }
}

// MARK: - Commands

/// Body for `POST /api/v1/command`.
///
/// VERIFY: command names — `ArtistSearch` (with `artistId`), `AlbumSearch`
/// (with `albumIds`) and `RefreshArtist`. Confirm against the running version.
public struct LidarrCommandRequest: Encodable, Sendable {
    public var name: String
    public var artistId: Int?
    public var albumIds: [Int]?

    public init(name: String, artistId: Int? = nil, albumIds: [Int]? = nil) {
        self.name = name
        self.artistId = artistId
        self.albumIds = albumIds
    }

    public static func artistSearch(artistId: Int) -> LidarrCommandRequest {
        LidarrCommandRequest(name: "ArtistSearch", artistId: artistId)
    }
    public static func albumSearch(albumIds: [Int]) -> LidarrCommandRequest {
        LidarrCommandRequest(name: "AlbumSearch", albumIds: albumIds)
    }
    public static func refreshArtist(artistId: Int) -> LidarrCommandRequest {
        LidarrCommandRequest(name: "RefreshArtist", artistId: artistId)
    }
}

public struct LidarrCommandResource: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String?
    public var status: String?
}

// MARK: - Editing

/// Body for `PUT /api/v1/artist/editor` — bulk-edits one or more artists. Only
/// the present fields change, so it serves single- and multi-item edits.
///
/// VERIFY: field names `artistIds`, `monitored`, `qualityProfileId`,
/// `metadataProfileId`, `rootFolderPath`, `moveFiles`.
public struct LidarrArtistEditorRequest: Encodable, Sendable {
    public var artistIds: [Int]
    public var monitored: Bool?
    public var qualityProfileId: Int?
    public var metadataProfileId: Int?
    public var rootFolderPath: String?
    public var moveFiles: Bool?

    public init(
        artistIds: [Int],
        monitored: Bool? = nil,
        qualityProfileId: Int? = nil,
        metadataProfileId: Int? = nil,
        rootFolderPath: String? = nil,
        moveFiles: Bool? = nil
    ) {
        self.artistIds = artistIds
        self.monitored = monitored
        self.qualityProfileId = qualityProfileId
        self.metadataProfileId = metadataProfileId
        self.rootFolderPath = rootFolderPath
        self.moveFiles = moveFiles
    }
}

/// Body for `PUT /api/v1/album/monitor` — toggles monitoring on individual albums.
///
/// VERIFY: `{ "albumIds": [...], "monitored": Bool }`.
public struct LidarrAlbumMonitorRequest: Encodable, Sendable {
    public var albumIds: [Int]
    public var monitored: Bool

    public init(albumIds: [Int], monitored: Bool) {
        self.albumIds = albumIds
        self.monitored = monitored
    }
}
