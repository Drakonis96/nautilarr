import SwiftUI
import NautilarrCore
import SonarrKit
import RadarrKit
import LidarrKit
import QBittorrentKit
import SABnzbdKit
import NZBGetKit
import TransmissionKit
import DelugeKit

/// A normalised status bucket so the whole queue can be filtered/sorted by state
/// regardless of which service or client an item comes from.
enum DownloadStatusCategory: String, CaseIterable, Identifiable {
    case downloading, seeding, completed, queued, paused, error

    var id: String { rawValue }

    var label: String {
        switch self {
        case .downloading: return "Downloading"
        case .seeding: return "Seeding"
        case .completed: return "Completed"
        case .queued: return "Queued"
        case .paused: return "Paused"
        case .error: return "Error"
        }
    }

    var symbol: String {
        switch self {
        case .downloading: return "arrow.down.circle"
        case .seeding: return "arrow.up.circle"
        case .completed: return "checkmark.circle"
        case .queued: return "clock"
        case .paused: return "pause.circle"
        case .error: return "exclamationmark.triangle"
        }
    }

    var color: Color {
        switch self {
        case .downloading: return Theme.teal
        case .seeding: return .green
        case .completed: return .blue
        case .queued: return .secondary
        case .paused: return .orange
        case .error: return .red
        }
    }
}

/// A download item normalised across services and download clients. Carries the
/// closures that know how to pause/resume, recheck and remove it from its source.
/// An action is `nil` when the source doesn't support it (e.g. *arr import queues
/// can be removed but not paused — pausing is the download client's job).
struct UnifiedDownload: Identifiable {
    let id: String
    let serviceType: ServiceType
    let instanceName: String
    let title: String
    let progress: Double
    let state: String
    let category: DownloadStatusCategory
    let isWarning: Bool
    let isError: Bool
    let isPaused: Bool
    let downloadClient: String?
    let size: Double?
    let errorMessage: String?
    /// Seconds spent seeding (torrent clients only).
    var seedingSeconds: Int?
    /// Share ratio (torrent clients only).
    var ratio: Double?
    let togglePause: (@MainActor () async -> Void)?
    let remove: (@MainActor (_ deleteData: Bool) async -> Void)?
    /// Force a re-check of the downloaded data (torrent clients only).
    var recheck: (@MainActor () async -> Void)? = nil
    /// *arr only: remove from the client AND add to the blocklist so the *arr
    /// re-searches for a different release. `nil` for download-client items.
    var blocklist: (@MainActor () async -> Void)? = nil

    var isSeeding: Bool { category == .seeding }
}

/// Unified download queue across the *arr import queues and the download clients
/// (qBittorrent, SABnzbd, NZBGet, Transmission, Deluge), with auto-refresh.
@MainActor
final class DownloadsViewModel: ObservableObject {
    @Published var items: [UnifiedDownload] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasServices = true
    @Published var seedLimitStatus: String?

    func load(store: InstanceStore, disabledClientIDs: Set<String> = []) async {
        let types: [ServiceType] = [.sonarr, .radarr, .lidarr, .qbittorrent, .sabnzbd, .nzbget, .transmission, .deluge]
        hasServices = types.contains { !store.instances(ofType: $0).isEmpty }
        guard hasServices else { items = []; return }
        func enabled(_ instance: ServiceInstance) -> Bool { !disabledClientIDs.contains(instance.id.uuidString) }

        if items.isEmpty { isLoading = true }
        defer { isLoading = false }

        var collected: [UnifiedDownload] = []
        var firstError: String?
        func note(_ error: Error) {
            firstError = firstError ?? ((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }

        // *arr import queues (removable, not pausable here).
        func arrCategory(progress: Double, isError: Bool) -> DownloadStatusCategory {
            if isError { return .error }
            return progress >= 1.0 ? .completed : .downloading
        }
        for instance in store.instances(ofType: .sonarr) {
            guard let client = store.sonarrClient(for: instance) else { continue }
            do {
                for item in try await client.queue(pageSize: 100).records {
                    let isError = item.trackedDownloadStatus?.lowercased() == "error"
                    collected.append(.init(
                        id: "sonarr-\(instance.id)-\(item.id)", serviceType: .sonarr, instanceName: instance.name,
                        title: item.title ?? "Unknown", progress: item.progress,
                        state: item.trackedDownloadState ?? item.status ?? "—",
                        category: arrCategory(progress: item.progress, isError: isError),
                        isWarning: item.trackedDownloadStatus?.lowercased() == "warning",
                        isError: isError,
                        isPaused: false, downloadClient: item.downloadClient,
                        size: item.size, errorMessage: item.errorMessage, togglePause: nil,
                        remove: { try? await client.removeQueueItem(id: item.id, removeFromClient: $0) },
                        blocklist: { try? await client.removeQueueItem(id: item.id, removeFromClient: true, blocklist: true) }
                    ))
                }
            } catch { note(error) }
        }
        for instance in store.instances(ofType: .radarr) {
            guard let client = store.radarrClient(for: instance) else { continue }
            do {
                for item in try await client.queue(pageSize: 100).records {
                    let isError = item.trackedDownloadStatus?.lowercased() == "error"
                    collected.append(.init(
                        id: "radarr-\(instance.id)-\(item.id)", serviceType: .radarr, instanceName: instance.name,
                        title: item.title ?? "Unknown", progress: item.progress,
                        state: item.trackedDownloadState ?? item.status ?? "—",
                        category: arrCategory(progress: item.progress, isError: isError),
                        isWarning: item.trackedDownloadStatus?.lowercased() == "warning",
                        isError: isError,
                        isPaused: false, downloadClient: item.downloadClient,
                        size: item.size, errorMessage: item.errorMessage, togglePause: nil,
                        remove: { try? await client.removeQueueItem(id: item.id, removeFromClient: $0) },
                        blocklist: { try? await client.removeQueueItem(id: item.id, removeFromClient: true, blocklist: true) }
                    ))
                }
            } catch { note(error) }
        }
        for instance in store.instances(ofType: .lidarr) {
            guard let client = store.lidarrClient(for: instance) else { continue }
            do {
                for item in try await client.queue(pageSize: 100).records {
                    let isError = item.trackedDownloadStatus?.lowercased() == "error"
                    collected.append(.init(
                        id: "lidarr-\(instance.id)-\(item.id)", serviceType: .lidarr, instanceName: instance.name,
                        title: item.title ?? "Unknown", progress: item.progress,
                        state: item.trackedDownloadState ?? item.status ?? "—",
                        category: arrCategory(progress: item.progress, isError: isError),
                        isWarning: item.trackedDownloadStatus?.lowercased() == "warning",
                        isError: isError,
                        isPaused: false, downloadClient: item.downloadClient,
                        size: item.size, errorMessage: item.errorMessage, togglePause: nil,
                        remove: { try? await client.removeQueueItem(id: item.id, removeFromClient: $0) },
                        blocklist: { try? await client.removeQueueItem(id: item.id, removeFromClient: true, blocklist: true) }
                    ))
                }
            } catch { note(error) }
        }

        // qBittorrent — pausable, removable, recheckable.
        for instance in store.instances(ofType: .qbittorrent) where enabled(instance) {
            guard let client = store.qbittorrentClient(for: instance) else { continue }
            do {
                for t in try await client.torrents() {
                    let paused = t.isPaused
                    collected.append(.init(
                        id: "qbit-\(instance.id)-\(t.hash)", serviceType: .qbittorrent, instanceName: instance.name,
                        title: t.name, progress: t.progress ?? 0, state: t.displayState,
                        category: qbitCategory(t),
                        isWarning: t.state == "stalledDL", isError: t.state == "error" || t.state == "missingFiles",
                        isPaused: paused, downloadClient: "qBittorrent",
                        size: t.size.map(Double.init), errorMessage: nil,
                        seedingSeconds: t.seedingTime, ratio: t.ratio,
                        togglePause: {
                            if paused { try? await client.resume(hashes: [t.hash]) }
                            else { try? await client.pause(hashes: [t.hash]) }
                        },
                        remove: { try? await client.delete(hashes: [t.hash], deleteFiles: $0) },
                        recheck: { try? await client.recheck(hashes: [t.hash]) }
                    ))
                }
            } catch { note(error) }
        }

        // SABnzbd — pausable & removable (usenet, no seeding).
        for instance in store.instances(ofType: .sabnzbd) where enabled(instance) {
            guard let client = store.sabnzbdClient(for: instance) else { continue }
            do {
                for slot in try await client.queue().slots {
                    let paused = slot.isPaused
                    collected.append(.init(
                        id: "sab-\(instance.id)-\(slot.nzoId)", serviceType: .sabnzbd, instanceName: instance.name,
                        title: slot.filename ?? "Unknown", progress: slot.progress,
                        state: slot.status ?? "—",
                        category: paused ? .paused : .downloading,
                        isWarning: false, isError: false,
                        isPaused: paused, downloadClient: "SABnzbd",
                        size: slot.sizeBytes, errorMessage: nil,
                        togglePause: {
                            if paused { try? await client.resume(nzoId: slot.nzoId) }
                            else { try? await client.pause(nzoId: slot.nzoId) }
                        },
                        remove: { try? await client.delete(nzoId: slot.nzoId, deleteFiles: $0) }
                    ))
                }
            } catch { note(error) }
        }

        // NZBGet — pausable & removable (usenet).
        for instance in store.instances(ofType: .nzbget) where enabled(instance) {
            guard let client = store.nzbgetClient(for: instance) else { continue }
            do {
                for g in try await client.groups() {
                    let paused = g.isPaused
                    collected.append(.init(
                        id: "nzbget-\(instance.id)-\(g.nzbID)", serviceType: .nzbget, instanceName: instance.name,
                        title: g.nzbName ?? "Unknown", progress: g.progress,
                        state: paused ? "Paused" : (g.status?.capitalized ?? "—"),
                        category: paused ? .paused : .downloading,
                        isWarning: false, isError: false, isPaused: paused, downloadClient: "NZBGet",
                        size: g.sizeBytes, errorMessage: nil,
                        togglePause: {
                            if paused { _ = try? await client.resumeGroup(id: g.nzbID) }
                            else { _ = try? await client.pauseGroup(id: g.nzbID) }
                        },
                        remove: { _ = try? await client.deleteGroup(id: g.nzbID, deleteFiles: $0) }
                    ))
                }
            } catch { note(error) }
        }

        // Transmission — pausable, removable, recheckable (torrents).
        for instance in store.instances(ofType: .transmission) where enabled(instance) {
            guard let client = store.transmissionClient(for: instance) else { continue }
            do {
                for t in try await client.torrents() {
                    let paused = t.isPaused
                    collected.append(.init(
                        id: "trans-\(instance.id)-\(t.id)", serviceType: .transmission, instanceName: instance.name,
                        title: t.name ?? "Unknown", progress: t.progress, state: t.displayState,
                        category: transmissionCategory(t),
                        isWarning: false, isError: t.hasError, isPaused: paused, downloadClient: "Transmission",
                        size: t.totalSize.map(Double.init), errorMessage: t.hasError ? t.errorString : nil,
                        seedingSeconds: t.secondsSeeding, ratio: t.uploadRatio,
                        togglePause: {
                            if paused { try? await client.start(ids: [t.id]) }
                            else { try? await client.stop(ids: [t.id]) }
                        },
                        remove: { try? await client.remove(ids: [t.id], deleteData: $0) },
                        recheck: { try? await client.verify(ids: [t.id]) }
                    ))
                }
            } catch { note(error) }
        }

        // Deluge — pausable, removable, recheckable (torrents).
        for instance in store.instances(ofType: .deluge) where enabled(instance) {
            guard let client = store.delugeClient(for: instance) else { continue }
            do {
                for t in try await client.torrents() {
                    let paused = t.isPaused
                    collected.append(.init(
                        id: "deluge-\(instance.id)-\(t.id)", serviceType: .deluge, instanceName: instance.name,
                        title: t.name ?? "Unknown", progress: t.fractionDone, state: t.state ?? "—",
                        category: delugeCategory(t),
                        isWarning: false, isError: t.hasError, isPaused: paused, downloadClient: "Deluge",
                        size: t.totalSize.map(Double.init), errorMessage: nil,
                        seedingSeconds: t.seedingTime, ratio: t.ratio,
                        togglePause: {
                            if paused { try? await client.resume(hashes: [t.id]) }
                            else { try? await client.pause(hashes: [t.id]) }
                        },
                        remove: { try? await client.remove(hash: t.id, removeData: $0) },
                        recheck: { try? await client.forceRecheck(hashes: [t.id]) }
                    ))
                }
            } catch { note(error) }
        }

        items = collected.sorted { $0.progress > $1.progress }
        errorMessage = firstError
    }

    // MARK: Status categorisation per client

    private func qbitCategory(_ t: QBTorrent) -> DownloadStatusCategory {
        switch t.state {
        case "error", "missingFiles": return .error
        case "pausedDL", "stoppedDL": return .paused
        case "pausedUP", "stoppedUP": return .completed
        case "uploading", "forcedUP", "stalledUP": return .seeding
        case "queuedDL", "queuedUP": return .queued
        default: return .downloading
        }
    }

    private func transmissionCategory(_ t: TransmissionTorrent) -> DownloadStatusCategory {
        if t.hasError { return .error }
        if t.isPaused { return t.progress >= 1.0 ? .completed : .paused }
        if t.isSeeding { return .seeding }
        if t.status == 3 { return .queued }
        return .downloading
    }

    private func delugeCategory(_ t: DelugeTorrent) -> DownloadStatusCategory {
        switch t.state?.lowercased() {
        case "error": return .error
        case "paused": return .paused
        case "seeding": return .seeding
        case "queued": return .queued
        default: return .downloading
        }
    }

    // MARK: Seed-time limit (client-side janitor)

    /// Applies the user's seed limit (by days and/or ratio) to seeding torrents
    /// that have exceeded it. Safe no-op unless enabled. Updates `seedLimitStatus`
    /// for a toast if it acted.
    func enforceSeedLimit(enabled: Bool, byDays: Bool, maxDays: Int,
                          byRatio: Bool, maxRatio: Double, action: SeedLimitAction) async {
        guard enabled, byDays || byRatio else { return }
        let daysLimit = maxDays * 86_400
        let overdue = items.filter { item in
            guard item.isSeeding, !item.isPaused else { return false }
            let daysExceeded = byDays && (item.seedingSeconds ?? 0) > daysLimit
            let ratioExceeded = byRatio && (item.ratio ?? 0) >= maxRatio
            return daysExceeded || ratioExceeded
        }
        guard !overdue.isEmpty else { return }
        for item in overdue {
            switch action {
            case .pause: await item.togglePause?()
            case .remove: await item.remove?(false)
            case .removeAndDelete: await item.remove?(true)
            }
        }
        let verb: String
        switch action {
        case .pause: verb = "Paused"
        case .remove: verb = "Removed"
        case .removeAndDelete: verb = "Removed & deleted"
        }
        seedLimitStatus = "\(verb) \(overdue.count) torrent\(overdue.count == 1 ? "" : "s") over the seed limit."
    }

    /// Pauses every configured download client (global "pause all").
    func pauseAllClients(store: InstanceStore) async {
        await forEachClient(store: store,
            qbit: { try await $0.pause(hashes: nil) },
            sab: { try await $0.pauseAll() },
            nzbget: { _ = try await $0.pauseAll() },
            transmission: { let ids = try await $0.torrents().map(\.id); if !ids.isEmpty { try await $0.stop(ids: ids) } },
            deluge: { let hashes = try await $0.torrents().map(\.id); if !hashes.isEmpty { try await $0.pause(hashes: hashes) } })
    }

    /// Resumes every configured download client (global "resume all").
    func resumeAllClients(store: InstanceStore) async {
        await forEachClient(store: store,
            qbit: { try await $0.resume(hashes: nil) },
            sab: { try await $0.resumeAll() },
            nzbget: { _ = try await $0.resumeAll() },
            transmission: { let ids = try await $0.torrents().map(\.id); if !ids.isEmpty { try await $0.start(ids: ids) } },
            deluge: { let hashes = try await $0.torrents().map(\.id); if !hashes.isEmpty { try await $0.resume(hashes: hashes) } })
    }

    private func forEachClient(
        store: InstanceStore,
        qbit: @escaping (QBittorrentClient) async throws -> Void,
        sab: @escaping (SABnzbdClient) async throws -> Void,
        nzbget: @escaping (NZBGetClient) async throws -> Void,
        transmission: @escaping (TransmissionClient) async throws -> Void,
        deluge: @escaping (DelugeClient) async throws -> Void
    ) async {
        for instance in store.instances(ofType: .qbittorrent) {
            if let c = store.qbittorrentClient(for: instance) { try? await qbit(c) }
        }
        for instance in store.instances(ofType: .sabnzbd) {
            if let c = store.sabnzbdClient(for: instance) { try? await sab(c) }
        }
        for instance in store.instances(ofType: .nzbget) {
            if let c = store.nzbgetClient(for: instance) { try? await nzbget(c) }
        }
        for instance in store.instances(ofType: .transmission) {
            if let c = store.transmissionClient(for: instance) { try? await transmission(c) }
        }
        for instance in store.instances(ofType: .deluge) {
            if let c = store.delugeClient(for: instance) { try? await deluge(c) }
        }
    }
}

/// Formats a seeding duration compactly, e.g. "3d 4h" or "12h" or "45m".
enum SeedFormat {
    static func duration(_ seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
