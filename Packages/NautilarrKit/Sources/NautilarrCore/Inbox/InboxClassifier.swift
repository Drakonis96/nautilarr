import Foundation

// MARK: - Inbox triage model
//
// Pure, dependency-free classification of "what is wrong right now" across the
// stack, so it can be unit-tested without any network or UI. The app maps its
// `UnifiedDownload`s and per-service health items into the neutral snapshots
// below, calls `InboxClassifier.classify`, then re-attaches the right one-tap
// fix action to each returned issue.

/// Severity of an inbox issue, ordered so the highest-priority sorts first.
public enum InboxSeverity: Int, Sendable, Comparable, Codable {
    case notice = 0, warning = 1, error = 2
    public static func < (lhs: InboxSeverity, rhs: InboxSeverity) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Maps an *arr/Prowlarr health `type` string to a severity (nil = ignore).
    public static func fromHealth(_ type: String?) -> InboxSeverity? {
        switch type?.lowercased() {
        case "error": return .error
        case "warning": return .warning
        case "notice": return .notice
        default: return nil   // "ok"/unknown — not an issue
        }
    }
}

/// The kind of problem, used to group the inbox and pick available actions.
public enum InboxKind: String, Sendable, Codable {
    case stuckDownload      // a download client item making no progress / errored
    case failedImport       // an *arr queue item blocked, failed or stuck importing
    case health             // an *arr/Prowlarr health-check warning or error
}

/// Neutral view of a queue item the classifier reasons about.
public struct InboxDownloadSnapshot: Sendable {
    public let id: String
    public let serviceType: ServiceType
    public let instanceName: String
    public let title: String
    /// True for torrent/usenet clients; false for *arr import queues. Separates
    /// the "stuck download" bucket from the "failed import" bucket.
    public let isDownloadClient: Bool
    /// `DownloadStatusCategory` raw value: downloading/seeding/completed/queued/paused/error.
    public let category: String
    public let state: String
    public let isWarning: Bool
    public let isError: Bool
    public let isPaused: Bool
    /// Current download rate in bytes/sec. `nil` when the source doesn't report
    /// it (stall detection is then skipped for this item).
    public let downloadSpeed: Int?
    public let progress: Double

    public init(id: String, serviceType: ServiceType, instanceName: String, title: String,
                isDownloadClient: Bool, category: String, state: String,
                isWarning: Bool, isError: Bool, isPaused: Bool,
                downloadSpeed: Int?, progress: Double) {
        self.id = id; self.serviceType = serviceType; self.instanceName = instanceName
        self.title = title; self.isDownloadClient = isDownloadClient; self.category = category
        self.state = state; self.isWarning = isWarning; self.isError = isError
        self.isPaused = isPaused; self.downloadSpeed = downloadSpeed; self.progress = progress
    }
}

/// Neutral view of an *arr/Prowlarr health-check item.
public struct InboxHealthSnapshot: Sendable {
    public let id: String
    public let serviceType: ServiceType
    public let instanceName: String
    public let message: String
    public let severity: InboxSeverity
    public let wikiURL: String?

    public init(id: String, serviceType: ServiceType, instanceName: String,
                message: String, severity: InboxSeverity, wikiURL: String?) {
        self.id = id; self.serviceType = serviceType; self.instanceName = instanceName
        self.message = message; self.severity = severity; self.wikiURL = wikiURL
    }
}

/// A classified issue (UI-agnostic). The app re-attaches actions by `sourceID`.
public struct InboxIssue: Sendable, Identifiable {
    public let id: String
    /// The originating download/health id, used to look up the fix action.
    public let sourceID: String
    public let kind: InboxKind
    public let severity: InboxSeverity
    public let title: String
    public let detail: String
    public let instanceName: String
    public let serviceType: ServiceType
    public let wikiURL: String?

    public init(id: String, sourceID: String, kind: InboxKind, severity: InboxSeverity,
                title: String, detail: String, instanceName: String,
                serviceType: ServiceType, wikiURL: String?) {
        self.id = id; self.sourceID = sourceID; self.kind = kind; self.severity = severity
        self.title = title; self.detail = detail; self.instanceName = instanceName
        self.serviceType = serviceType; self.wikiURL = wikiURL
    }
}

public enum InboxClassifier {
    /// *arr `trackedDownloadState` values that indicate an import problem rather
    /// than normal progress.
    static let importProblemStates: Set<String> = [
        "importpending", "importblocked", "importfailed", "failedpending"
    ]

    /// Classifies the current downloads + health into a prioritised issue list.
    ///
    /// `stallSince` carries, across refreshes, the first time each item was seen
    /// at 0 B/s; the returned `stallSince` keeps only items still stalling so the
    /// caller can persist it. An item counts as a *stuck download* once it has
    /// been at 0 B/s for at least `stallThreshold` seconds.
    public static func classify(
        downloads: [InboxDownloadSnapshot],
        health: [InboxHealthSnapshot],
        stallSince: [String: Date],
        now: Date,
        stallThreshold: TimeInterval
    ) -> (issues: [InboxIssue], stallSince: [String: Date]) {
        var issues: [InboxIssue] = []
        var newStall: [String: Date] = [:]

        for d in downloads {
            if d.isDownloadClient {
                // Errored client item — always an issue regardless of speed.
                if d.isError || d.category == DownloadCategoryRaw.error {
                    issues.append(InboxIssue(
                        id: "stuck-\(d.id)", sourceID: d.id, kind: .stuckDownload, severity: .error,
                        title: d.title,
                        detail: "Download error · \(d.state) · \(d.instanceName)",
                        instanceName: d.instanceName, serviceType: d.serviceType, wikiURL: nil))
                    continue
                }
                // Stall detection: actively downloading but reporting 0 B/s.
                let active = !d.isPaused && d.progress < 1.0
                    && (d.category == DownloadCategoryRaw.downloading || d.category == DownloadCategoryRaw.queued)
                if active, let speed = d.downloadSpeed, speed == 0 {
                    let since = stallSince[d.id] ?? now
                    newStall[d.id] = since
                    if now.timeIntervalSince(since) >= stallThreshold {
                        issues.append(InboxIssue(
                            id: "stuck-\(d.id)", sourceID: d.id, kind: .stuckDownload, severity: .warning,
                            title: d.title,
                            detail: "Stalled at \(Int(d.progress * 100))% · no data for \(Self.elapsed(now.timeIntervalSince(since))) · \(d.instanceName)",
                            instanceName: d.instanceName, serviceType: d.serviceType, wikiURL: nil))
                    }
                }
            } else {
                // *arr import queue item.
                let stateKey = d.state.lowercased().replacingOccurrences(of: " ", with: "")
                if d.isError {
                    issues.append(InboxIssue(
                        id: "import-\(d.id)", sourceID: d.id, kind: .failedImport, severity: .error,
                        title: d.title,
                        detail: "Import failed · \(d.state) · \(d.instanceName)",
                        instanceName: d.instanceName, serviceType: d.serviceType, wikiURL: nil))
                } else if d.isWarning || importProblemStates.contains(stateKey) {
                    issues.append(InboxIssue(
                        id: "import-\(d.id)", sourceID: d.id, kind: .failedImport, severity: .warning,
                        title: d.title,
                        detail: "Import needs attention · \(d.state) · \(d.instanceName)",
                        instanceName: d.instanceName, serviceType: d.serviceType, wikiURL: nil))
                }
            }
        }

        for h in health {
            issues.append(InboxIssue(
                id: "health-\(h.id)", sourceID: h.id, kind: .health, severity: h.severity,
                title: h.message,
                detail: "\(h.instanceName) health check",
                instanceName: h.instanceName, serviceType: h.serviceType, wikiURL: h.wikiURL))
        }

        // Highest severity first, then by service & title for stability.
        issues.sort {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        return (issues, newStall)
    }

    /// Compact "no data for" string, e.g. "32m" or "1h 5m".
    static func elapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(max(1, m))m"
    }
}

/// Raw values of the app's `DownloadStatusCategory`, duplicated here as plain
/// strings so the core stays UI-free. Keep in sync with that enum.
enum DownloadCategoryRaw {
    static let downloading = "downloading"
    static let queued = "queued"
    static let error = "error"
}
