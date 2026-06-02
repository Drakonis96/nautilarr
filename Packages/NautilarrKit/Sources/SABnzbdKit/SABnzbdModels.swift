import Foundation

/// SABnzbd reports most numeric values as strings; these helpers parse them
/// leniently.
enum SABParse {
    static func double(_ s: String?) -> Double? { s.flatMap { Double($0) } }
}

/// `?mode=version` — used for the connection test.
public struct SABVersion: Codable, Sendable, Equatable {
    public var version: String?
}

/// A single download job in the queue.
public struct SABSlot: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { nzoId }
    public var nzoId: String
    public var filename: String?
    /// `Downloading`, `Paused`, `Queued`, `Fetching`, …
    public var status: String?
    /// Percentage complete as a string, e.g. `"45"`.
    public var percentage: String?
    /// Total size in MB, as a string.
    public var mb: String?
    /// Remaining size in MB, as a string.
    public var mbleft: String?
    public var timeleft: String?
    public var cat: String?

    private enum CodingKeys: String, CodingKey {
        case nzoId = "nzo_id"
        case filename, status, percentage, mb, mbleft, timeleft, cat
    }

    /// Fraction complete, `0...1`.
    public var progress: Double {
        if let pct = SABParse.double(percentage) { return max(0, min(1, pct / 100)) }
        guard let mb = SABParse.double(mb), mb > 0, let left = SABParse.double(mbleft) else { return 0 }
        return max(0, min(1, (mb - left) / mb))
    }

    public var isPaused: Bool { status?.lowercased() == "paused" }
    public var sizeBytes: Double? { SABParse.double(mb).map { $0 * 1_048_576 } }
}

/// The queue object from `?mode=queue&output=json` (wrapped in `{"queue": …}`).
public struct SABQueue: Codable, Sendable, Equatable {
    public var status: String?
    /// Human-readable speed, e.g. `"1.2 M"`.
    public var speed: String?
    public var sizeleft: String?
    public var mbleft: String?
    public var timeleft: String?
    public var paused: Bool?
    public var slots: [SABSlot]

    public var isPaused: Bool { paused ?? (status?.lowercased() == "paused") }
}

struct SABQueueResponse: Codable, Sendable {
    var queue: SABQueue
}
