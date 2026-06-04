import SwiftUI
import NautilarrCore
import SonarrKit
import RadarrKit
import LidarrKit
import ProwlarrKit

/// Backs the Activity Inbox: aggregates what's wrong right now — stalled/errored
/// downloads, failed or stuck *arr imports, and service health warnings — into a
/// single prioritised list with one-tap fixes. Reuses `DownloadsViewModel` for
/// the unified queue (and its action closures) and the per-service `health()`
/// endpoints, then runs the pure `InboxClassifier`.
@MainActor
final class InboxViewModel: ObservableObject {
    /// A classified issue paired with the download it came from (for actions).
    struct Entry: Identifiable {
        let issue: InboxIssue
        let download: UnifiedDownload?
        var id: String { issue.id }
    }

    @Published var entries: [Entry] = []
    @Published var isLoading = false
    @Published var hasServices = true

    private let downloads = DownloadsViewModel()
    /// Persisted across refreshes: first time each item was seen at 0 B/s.
    private var stallSince: [String: Date] = [:]

    var errorCount: Int { entries.filter { $0.issue.severity == .error }.count }
    var warningCount: Int { entries.filter { $0.issue.severity == .warning }.count }

    func entries(for filter: InboxFilter) -> [Entry] {
        switch filter {
        case .all: return entries
        case .downloads: return entries.filter { $0.issue.kind != .health }
        case .health: return entries.filter { $0.issue.kind == .health }
        }
    }

    func load(store: InstanceStore, settings: AppSettings) async {
        let mediaTypes: [ServiceType] = [.sonarr, .radarr, .lidarr, .qbittorrent, .sabnzbd, .nzbget, .transmission, .deluge, .prowlarr]
        hasServices = mediaTypes.contains { !store.instances(ofType: $0).isEmpty }
        guard hasServices else { entries = []; return }

        if entries.isEmpty { isLoading = true }
        defer { isLoading = false }

        // 1. Unified download queue (carries pause/remove/blocklist/retry closures).
        await downloads.load(store: store, disabledClientIDs: settings.disabledClientIDs)
        let items = downloads.items

        // 2. Per-service health, concurrently.
        let health = await Self.loadHealth(store: store)

        // 3. Classify (pure).
        let snapshots = items.map { d in
            InboxDownloadSnapshot(
                id: d.id, serviceType: d.serviceType, instanceName: d.instanceName, title: d.title,
                isDownloadClient: d.isDownloadClient, category: d.category.rawValue, state: d.state,
                isWarning: d.isWarning, isError: d.isError, isPaused: d.isPaused,
                downloadSpeed: d.downloadSpeed, progress: d.progress)
        }
        let result = InboxClassifier.classify(
            downloads: snapshots, health: health, stallSince: stallSince,
            now: Date(), stallThreshold: TimeInterval(settings.inboxStallMinutes * 60))
        stallSince = result.stallSince

        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        entries = result.issues.map { Entry(issue: $0, download: byID[$0.sourceID]) }
    }

    // MARK: - Health loading (off the main actor)

    private static func loadHealth(store: InstanceStore) async -> [InboxHealthSnapshot] {
        var producers: [@Sendable () async -> [InboxHealthSnapshot]] = []
        for instance in store.instances(ofType: .sonarr) {
            guard let c = store.sonarrClient(for: instance) else { continue }
            producers.append {
                guard let items = try? await c.health() else { return [] }
                return items.compactMap { snapshot(instance, .sonarr, $0.severity.rawValue, $0.message, $0.wikiUrl, $0.source) }
            }
        }
        for instance in store.instances(ofType: .radarr) {
            guard let c = store.radarrClient(for: instance) else { continue }
            producers.append {
                guard let items = try? await c.health() else { return [] }
                return items.compactMap { snapshot(instance, .radarr, $0.severity.rawValue, $0.message, $0.wikiUrl, $0.source) }
            }
        }
        for instance in store.instances(ofType: .lidarr) {
            guard let c = store.lidarrClient(for: instance) else { continue }
            producers.append {
                guard let items = try? await c.health() else { return [] }
                return items.compactMap { snapshot(instance, .lidarr, $0.severity.rawValue, $0.message, $0.wikiUrl, $0.source) }
            }
        }
        for instance in store.instances(ofType: .prowlarr) {
            guard let c = store.prowlarrClient(for: instance) else { continue }
            producers.append {
                guard let items = try? await c.health() else { return [] }
                return items.compactMap { snapshot(instance, .prowlarr, $0.severity.rawValue, $0.message, $0.wikiUrl, $0.source) }
            }
        }
        return await withTaskGroup(of: [InboxHealthSnapshot].self) { group in
            for p in producers { group.addTask { await p() } }
            var all: [InboxHealthSnapshot] = []
            for await r in group { all += r }
            return all
        }
    }

    /// Builds a health snapshot, dropping `ok`/unknown items that aren't issues.
    nonisolated private static func snapshot(_ instance: ServiceInstance, _ type: ServiceType,
                                             _ severity: String, _ message: String?,
                                             _ wikiURL: String?, _ source: String?) -> InboxHealthSnapshot? {
        guard let sev = InboxSeverity.fromHealth(severity) else { return nil }
        let id = "\(type.rawValue)-\(instance.id)-\(source ?? "")-\(message ?? "")"
        return InboxHealthSnapshot(id: id, serviceType: type, instanceName: instance.name,
                                   message: message ?? "Health check", severity: sev, wikiURL: wikiURL)
    }
}

/// The inbox's top-level filter chips.
enum InboxFilter: String, CaseIterable, Identifiable {
    case all, downloads, health
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .downloads: return "Downloads"
        case .health: return "Health"
        }
    }
    var symbol: String {
        switch self {
        case .all: return "tray.full"
        case .downloads: return "arrow.down.circle"
        case .health: return "stethoscope"
        }
    }
}
