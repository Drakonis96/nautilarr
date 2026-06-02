import Foundation

/// A generic paged envelope used by Sonarr's `/queue` and `/history` endpoints.
public struct SonarrPaged<Record: Codable & Sendable>: Codable, Sendable {
    public var page: Int?
    public var pageSize: Int?
    public var totalRecords: Int?
    public var records: [Record]
}

/// An item in the download queue (`GET /api/v3/queue`).
public struct SonarrQueueItem: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var seriesId: Int?
    public var episodeId: Int?
    public var title: String?
    public var status: String?
    /// `downloading`, `completed`, `warning`, `failed`, `delay`, …
    public var trackedDownloadStatus: String?
    public var trackedDownloadState: String?
    public var size: Double?
    public var sizeleft: Double?
    public var timeleft: String?
    public var estimatedCompletionTime: Date?
    public var downloadClient: String?
    public var protocolName: String?
    public var indexer: String?
    public var quality: SonarrQualityModel?
    public var errorMessage: String?
    public var series: SonarrSeries?
    public var episode: SonarrEpisode?

    private enum CodingKeys: String, CodingKey {
        case id, seriesId, episodeId, title, status
        case trackedDownloadStatus, trackedDownloadState
        case size, sizeleft, timeleft, estimatedCompletionTime
        case downloadClient, indexer, quality, errorMessage, series, episode
        case protocolName = "protocol"
    }

    /// Fraction complete in `0...1`.
    public var progress: Double {
        guard let size, size > 0, let sizeleft else { return 0 }
        return max(0, min(1, (size - sizeleft) / size))
    }
}

public typealias SonarrQueue = SonarrPaged<SonarrQueueItem>
