import Foundation

// MARK: - Request → availability pipeline
//
// Correlates a request (Overseerr/Jellyseerr) with the *arr download queue to
// place each title on a single timeline: Requested → Approved → Grabbed →
// Downloading → Importing → Available. Pure and dependency-free so the staging
// rules are unit-testable; the app supplies the queue match (looked up by tmdbId
// with a title+year fallback).

/// One stage of a title's journey from request to playable. `rawValue` is the
/// step index, so stages compare and drive a stepper directly.
public enum PipelineStage: Int, Sendable, CaseIterable, Comparable, Codable {
    case requested = 0   // awaiting approval
    case approved = 1    // approved, handed to the *arr, not grabbed yet
    case grabbed = 2     // a release was grabbed / *arr is processing
    case downloading = 3 // download client is pulling it (has progress)
    case importing = 4   // downloaded, *arr is importing/renaming
    case available = 5   // imported and playable

    public static func < (lhs: PipelineStage, rhs: PipelineStage) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .requested: return "Requested"
        case .approved: return "Approved"
        case .grabbed: return "Grabbed"
        case .downloading: return "Downloading"
        case .importing: return "Importing"
        case .available: return "Available"
        }
    }

    public var symbol: String {
        switch self {
        case .requested: return "paperplane"
        case .approved: return "checkmark.seal"
        case .grabbed: return "magnifyingglass"
        case .downloading: return "arrow.down.circle"
        case .importing: return "tray.and.arrow.down"
        case .available: return "checkmark.circle.fill"
        }
    }
}

/// The single best-matching *arr queue item for a title.
public struct PipelineQueueMatch: Sendable, Equatable {
    public let progress: Double
    /// `trackedDownloadState`, e.g. "downloading", "importPending", "importing".
    public let trackedState: String
    public let hasError: Bool

    public init(progress: Double, trackedState: String, hasError: Bool) {
        self.progress = progress; self.trackedState = trackedState; self.hasError = hasError
    }

    /// Reduces several queue items (e.g. multiple episodes of one series) to the
    /// most advanced one: prefer importing, then highest progress, then errored.
    public static func best(_ matches: [PipelineQueueMatch]) -> PipelineQueueMatch? {
        guard !matches.isEmpty else { return nil }
        if let importing = matches.first(where: { $0.trackedState.lowercased().contains("import") }) {
            return importing
        }
        return matches.max { $0.progress < $1.progress }
    }
}

public enum PipelineCorrelator {
    // Overseerr request-approval states.
    static let requestPending = 1, requestApproved = 2, requestDeclined = 3
    // Overseerr media availability states.
    static let mediaProcessing = 3, mediaPartiallyAvailable = 4, mediaAvailable = 5

    /// Places a title on the pipeline from its request status, media-availability
    /// status, and the best-matching queue item (if any). Returns the stage and a
    /// 0…1 progress for the active step.
    public static func stage(requestStatus: Int, mediaStatus: Int?, match: PipelineQueueMatch?) -> (stage: PipelineStage, progress: Double) {
        // Fully available trumps everything.
        if mediaStatus == mediaAvailable { return (.available, 1) }
        // Still awaiting approval.
        if requestStatus == requestPending { return (.requested, 0) }

        // Approved (or processing): refine using the live queue if we matched one.
        if let match {
            let state = match.trackedState.lowercased().replacingOccurrences(of: " ", with: "")
            if state.contains("import") { return (.importing, max(match.progress, 0.99)) }
            if match.progress >= 1.0 { return (.importing, 1) }
            if match.progress > 0 { return (.downloading, match.progress) }
            return (.grabbed, 0)
        }

        // Approved but nothing in the queue yet — fall back to Overseerr's status.
        switch mediaStatus {
        case mediaPartiallyAvailable: return (.available, 1) // some episodes present
        case mediaProcessing: return (.grabbed, 0)           // searching / grabbing
        default: return (.approved, 0)
        }
    }

    /// Whether a request should appear in the pipeline at all (declined are hidden).
    public static func isVisible(requestStatus: Int) -> Bool {
        requestStatus != requestDeclined
    }

    /// Normalises a title for the fallback (title+year) match: lowercased,
    /// alphanumerics only, with a trailing 4-digit year appended when known.
    public static func matchKey(title: String, year: Int?) -> String {
        let cleaned = title.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
        if let year { return "\(cleaned)#\(year)" }
        return cleaned
    }
}
