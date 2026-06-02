import Foundation

/// A torrent from `GET /api/v2/torrents/info`.
public struct QBTorrent: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { hash }
    public var hash: String
    public var name: String
    public var size: Int64?
    /// Fraction complete, `0...1`.
    public var progress: Double?
    public var dlspeed: Int64?
    public var upspeed: Int64?
    /// Raw qBittorrent state, e.g. `downloading`, `pausedDL`, `stalledUP`.
    public var state: String?
    public var category: String?
    public var tags: String?
    public var ratio: Double?
    /// Seconds remaining; `8640000` is qBittorrent's "infinity" sentinel.
    public var eta: Int?
    public var numSeeds: Int?
    public var numLeechs: Int?
    public var addedOn: Int?
    public var amountLeft: Int64?
    /// Seconds the torrent has been seeding. Used for the seed-time limit.
    public var seedingTime: Int?

    private enum CodingKeys: String, CodingKey {
        case hash, name, size, progress, dlspeed, upspeed, state, category, tags, ratio, eta
        case numSeeds = "num_seeds"
        case numLeechs = "num_leechs"
        case addedOn = "added_on"
        case amountLeft = "amount_left"
        case seedingTime = "seeding_time"
    }

    public var isPaused: Bool {
        guard let state else { return false }
        return state.lowercased().contains("paused") || state.lowercased().contains("stopped")
    }

    public var isComplete: Bool { (progress ?? 0) >= 1.0 }

    /// Friendly state label.
    public var displayState: String {
        switch state {
        case "downloading", "forcedDL": return "Downloading"
        case "metaDL": return "Fetching metadata"
        case "stalledDL": return "Stalled"
        case "uploading", "forcedUP": return "Seeding"
        case "stalledUP": return "Seeding (idle)"
        case "pausedDL", "stoppedDL": return "Paused"
        case "pausedUP", "stoppedUP": return "Completed"
        case "queuedDL", "queuedUP": return "Queued"
        case "checkingDL", "checkingUP", "checkingResumeData": return "Checking"
        case "error", "missingFiles": return "Error"
        case "moving": return "Moving"
        default: return state?.capitalized ?? "Unknown"
        }
    }
}

/// Global transfer info from `GET /api/v2/transfer/info`.
public struct QBTransferInfo: Codable, Sendable, Equatable {
    public var dlInfoSpeed: Int64?
    public var upInfoSpeed: Int64?
    public var dlInfoData: Int64?
    public var upInfoData: Int64?
    public var connectionStatus: String?

    private enum CodingKeys: String, CodingKey {
        case dlInfoSpeed = "dl_info_speed"
        case upInfoSpeed = "up_info_speed"
        case dlInfoData = "dl_info_data"
        case upInfoData = "up_info_data"
        case connectionStatus = "connection_status"
    }
}

/// qBittorrent application version (`GET /api/v2/app/version`) is plain text, so
/// the connection test reads it as a string rather than JSON.
public struct QBVersion: Sendable, Equatable {
    public var version: String
}
