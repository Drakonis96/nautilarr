import SwiftUI
import NautilarrCore
import SonarrKit
import RadarrKit
import LidarrKit
import TautulliKit
import JellystatKit
import QBittorrentKit
import SABnzbdKit
import NZBGetKit
import TransmissionKit
import DelugeKit
import ProwlarrKit
import BazarrKit
import OverseerrKit
import UnraidKit
import TorznabKit

/// Aggregates dashboard data across EVERY configured service — media managers,
/// download clients, indexers, request and monitoring services — so the Home
/// screen reflects the whole stack, not just Sonarr/Radarr. Each service loads
/// concurrently and a failed load surfaces an error card rather than vanishing.
@MainActor
final class HomeViewModel: ObservableObject {
    enum Level: Sendable { case notice, warning, error }

    struct ServiceStat: Identifiable, Sendable {
        let id = UUID()
        let instanceName: String
        let type: ServiceType
        let headline: String          // e.g. "176 Series"
        let metrics: [Metric]
        var librarySize: Int64? = nil
        var freeSpace: Int64? = nil
        var errorMessage: String? = nil
        /// Set for download clients so the dashboard card can open the per-client
        /// management screen.
        var instanceID: UUID? = nil
        /// Media services only: title count (series/movies/artists) and file count,
        /// used to build the aggregate Library Statistics card.
        var titleCount: Int? = nil
        var fileCount: Int? = nil
    }

    /// Aggregate counts across all media services, for the Library Statistics card.
    struct LibrarySummary: Sendable {
        var series = 0, movies = 0, artists = 0, files = 0
        var size: Int64 = 0
        var isEmpty: Bool { series == 0 && movies == 0 && artists == 0 }
    }
    struct Metric: Identifiable, Sendable {
        let id = UUID()
        let label: String
        let value: String
    }
    struct HealthLine: Identifiable, Sendable {
        let id = UUID()
        let instanceName: String
        let message: String
        let level: Level
    }
    struct DownloadLine: Identifiable, Sendable {
        let id = UUID()
        let title: String
        let progress: Double
    }
    struct UpcomingLine: Identifiable, Sendable {
        let id = UUID()
        let title: String
        let subtitle: String
        let date: Date?
        let instance: ServiceInstance
        let posterURLString: String?
        /// The library item this maps to, so tapping the poster opens its detail.
        var mediaEntry: MediaEntry?
    }
    struct StreamLine: Identifiable, Sendable {
        let id = UUID()
        let title: String
        let subtitle: String
        let progress: Double
        let transcoding: Bool
    }

    /// One contribution produced by a per-service loader, merged after all run.
    private enum Contribution: Sendable {
        case stat(ServiceStat)
        case health([HealthLine])
        case downloads([DownloadLine])
        case upcoming([UpcomingLine])
        case streams([StreamLine])
    }

    @Published var serviceStats: [ServiceStat] = []
    @Published var health: [HealthLine] = []
    @Published var downloads: [DownloadLine] = []
    @Published var upcoming: [UpcomingLine] = []
    @Published var streams: [StreamLine] = []
    @Published var isLoading = false
    @Published var hasServices = true

    /// Totals across the loaded media services.
    var librarySummary: LibrarySummary {
        var summary = LibrarySummary()
        for stat in serviceStats {
            switch stat.type {
            case .sonarr: summary.series += stat.titleCount ?? 0
            case .radarr: summary.movies += stat.titleCount ?? 0
            case .lidarr: summary.artists += stat.titleCount ?? 0
            default: continue
            }
            summary.files += stat.fileCount ?? 0
            summary.size += stat.librarySize ?? 0
        }
        return summary
    }

    func load(store: InstanceStore) async {
        hasServices = !store.instancesInActiveNetwork.isEmpty
        guard hasServices else {
            serviceStats = []; health = []; downloads = []; upcoming = []; streams = []
            return
        }

        if serviceStats.isEmpty { isLoading = true }
        defer { isLoading = false }

        // Look ~30 days ahead so upcoming movies (which release less often than
        // episodes) actually appear, not just the next week of TV.
        let weekEnd = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()

        // Build the per-service loaders on the main actor (the store is
        // @MainActor), then run them all CONCURRENTLY so one slow/unreachable
        // service can't block the dashboard.
        var producers: [@Sendable () async -> [Contribution]] = []

        for instance in store.instances(ofType: .sonarr) {
            guard let c = store.sonarrClient(for: instance) else { continue }
            producers.append { await Self.loadSonarr(instance: instance, client: c, weekEnd: weekEnd) }
        }
        for instance in store.instances(ofType: .radarr) {
            guard let c = store.radarrClient(for: instance) else { continue }
            producers.append { await Self.loadRadarr(instance: instance, client: c, weekEnd: weekEnd) }
        }
        for instance in store.instances(ofType: .lidarr) {
            guard let c = store.lidarrClient(for: instance) else { continue }
            producers.append { await Self.loadLidarr(instance: instance, client: c) }
        }
        for instance in store.instances(ofType: .tautulli) {
            guard let c = store.tautulliClient(for: instance) else { continue }
            producers.append { await Self.loadTautulli(instance: instance, client: c) }
        }
        for instance in store.instances(ofType: .jellystat) {
            guard let c = store.jellystatClient(for: instance) else { continue }
            producers.append { await Self.loadJellystat(instance: instance, client: c) }
        }
        for instance in store.instances(ofType: .qbittorrent) {
            guard let c = store.qbittorrentClient(for: instance) else { continue }
            producers.append { await Self.loadQBittorrent(instance: instance, client: c) }
        }
        for instance in store.instances(ofType: .transmission) {
            guard let c = store.transmissionClient(for: instance) else { continue }
            producers.append { await Self.loadTransmission(instance: instance, client: c) }
        }
        for instance in store.instances(ofType: .deluge) {
            guard let c = store.delugeClient(for: instance) else { continue }
            producers.append { await Self.loadDeluge(instance: instance, client: c) }
        }
        for instance in store.instances(ofType: .sabnzbd) {
            guard let c = store.sabnzbdClient(for: instance) else { continue }
            producers.append { await Self.loadSABnzbd(instance: instance, client: c) }
        }
        for instance in store.instances(ofType: .nzbget) {
            guard let c = store.nzbgetClient(for: instance) else { continue }
            producers.append { await Self.loadNZBGet(instance: instance, client: c) }
        }
        for instance in store.instances(ofType: .prowlarr) {
            guard let c = store.prowlarrClient(for: instance) else { continue }
            producers.append { await Self.loadProwlarr(instance: instance, client: c) }
        }
        for instance in store.instances(ofType: .bazarr) {
            guard let c = store.bazarrClient(for: instance) else { continue }
            producers.append { await Self.loadBazarr(instance: instance, client: c) }
        }
        for instance in store.instances(ofType: .overseerr) {
            guard let c = store.overseerrClient(for: instance) else { continue }
            producers.append { await Self.loadOverseerr(instance: instance, client: c) }
        }
        for instance in store.instances(ofType: .unraid) {
            guard let c = store.unraidClient(for: instance) else { continue }
            producers.append { await Self.loadUnraid(instance: instance, client: c) }
        }
        for instance in store.instances(ofType: .nzbhydra2) + store.instances(ofType: .jackett) {
            guard let c = store.torznabClient(for: instance) else { continue }
            producers.append { await Self.loadTorznab(instance: instance, client: c) }
        }

        let contributions = await withTaskGroup(of: [Contribution].self) { group in
            for producer in producers { group.addTask { await producer() } }
            var all: [Contribution] = []
            for await result in group { all.append(contentsOf: result) }
            return all
        }

        var stats: [ServiceStat] = []
        var health: [HealthLine] = []
        var downloads: [DownloadLine] = []
        var upcoming: [UpcomingLine] = []
        var streams: [StreamLine] = []
        for contribution in contributions {
            switch contribution {
            case let .stat(s): stats.append(s)
            case let .health(h): health += h
            case let .downloads(d): downloads += d
            case let .upcoming(u): upcoming += u
            case let .streams(s): streams += s
            }
        }

        self.serviceStats = stats.sorted {
            ($0.type.rawValue, $0.instanceName) < ($1.type.rawValue, $1.instanceName)
        }
        self.health = health
        self.downloads = downloads
        self.streams = streams
        self.upcoming = Array(upcoming.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }.prefix(15))
    }

    // MARK: - Per-service loaders (run off the main actor)

    nonisolated private static func loadSonarr(instance: ServiceInstance, client: SonarrClient, weekEnd: Date) async -> [Contribution] {
        var out: [Contribution] = []
        do {
            let series = try await client.series()
            let episodes = series.reduce(0) { $0 + ($1.statistics?.totalEpisodeCount ?? 0) }
            let files = series.reduce(0) { $0 + ($1.statistics?.episodeFileCount ?? 0) }
            let size = series.reduce(Int64(0)) { $0 + ($1.statistics?.sizeOnDisk ?? 0) }
            let free = try? await client.rootFolders().first?.freeSpace
            out.append(.stat(ServiceStat(
                instanceName: instance.name, type: .sonarr,
                headline: "\(series.count) Series",
                metrics: [Metric(label: "Episodes", value: "\(episodes)"), Metric(label: "Files", value: "\(files)")],
                librarySize: size, freeSpace: free ?? nil, titleCount: series.count, fileCount: files)))
        } catch {
            out.append(.stat(errorStat(instance, .sonarr, error)))
        }
        if let items = try? await client.health() {
            out.append(.health(items.compactMap { item in
                level(item.severity.rawValue).map { HealthLine(instanceName: instance.name, message: item.message ?? "—", level: $0) }
            }))
        }
        if let q = try? await client.queue(pageSize: 20) {
            out.append(.downloads(q.records.map { DownloadLine(title: $0.title ?? "Unknown", progress: $0.progress) }))
        }
        if let cal = try? await client.calendar(start: Date(), end: weekEnd, unmonitored: true) {
            out.append(.upcoming(cal.sorted { ($0.airDateUtc ?? .distantFuture) < ($1.airDateUtc ?? .distantFuture) }
                .map { UpcomingLine(title: $0.series?.title ?? "Series",
                                    subtitle: "\($0.seasonEpisodeCode) · \($0.title ?? "")",
                                    date: $0.airDateUtc, instance: instance,
                                    posterURLString: $0.series?.imageURL(coverType: "poster"),
                                    mediaEntry: $0.series.map { .series(instance: instance, series: $0) }) }))
        }
        return out
    }

    nonisolated private static func loadRadarr(instance: ServiceInstance, client: RadarrClient, weekEnd: Date) async -> [Contribution] {
        var out: [Contribution] = []
        do {
            let movies = try await client.movies()
            let files = movies.filter { $0.hasFile == true }.count
            let size = movies.reduce(Int64(0)) { $0 + ($1.sizeOnDisk ?? 0) }
            let free = try? await client.rootFolders().first?.freeSpace
            out.append(.stat(ServiceStat(
                instanceName: instance.name, type: .radarr,
                headline: "\(movies.count) Movies",
                metrics: [Metric(label: "Files", value: "\(files)")],
                librarySize: size, freeSpace: free ?? nil, titleCount: movies.count, fileCount: files)))
        } catch {
            out.append(.stat(errorStat(instance, .radarr, error)))
        }
        if let items = try? await client.health() {
            out.append(.health(items.compactMap { item in
                level(item.severity.rawValue).map { HealthLine(instanceName: instance.name, message: item.message ?? "—", level: $0) }
            }))
        }
        if let q = try? await client.queue(pageSize: 20) {
            out.append(.downloads(q.records.map { DownloadLine(title: $0.title ?? "Unknown", progress: $0.progress) }))
        }
        if let cal = try? await client.calendar(start: Date(), end: weekEnd, unmonitored: true) {
            out.append(.upcoming(cal.map { UpcomingLine(title: $0.title, subtitle: "Movie",
                                                        date: $0.digitalRelease ?? $0.physicalRelease ?? $0.inCinemas,
                                                        instance: instance, posterURLString: $0.imageURL(coverType: "poster"),
                                                        mediaEntry: .movie(instance: instance, movie: $0)) }))
        }
        return out
    }

    nonisolated private static func loadLidarr(instance: ServiceInstance, client: LidarrClient) async -> [Contribution] {
        do {
            let artists = try await client.artists()
            let tracks = artists.reduce(0) { $0 + ($1.statistics?.trackCount ?? 0) }
            let files = artists.reduce(0) { $0 + ($1.statistics?.trackFileCount ?? 0) }
            let size = artists.reduce(Int64(0)) { $0 + ($1.statistics?.sizeOnDisk ?? 0) }
            let free = try? await client.rootFolders().first?.freeSpace
            return [.stat(ServiceStat(
                instanceName: instance.name, type: .lidarr,
                headline: "\(artists.count) Artists",
                metrics: [Metric(label: "Tracks", value: "\(tracks)")],
                librarySize: size, freeSpace: free ?? nil, titleCount: artists.count, fileCount: files))]
        } catch {
            return [.stat(errorStat(instance, .lidarr, error))]
        }
    }

    nonisolated private static func loadTautulli(instance: ServiceInstance, client: TautulliClient) async -> [Contribution] {
        do {
            let activity = try await client.activity()
            let streams = activity.sessions.map {
                StreamLine(title: $0.displayTitle,
                           subtitle: [$0.user, $0.player].compactMap { $0 }.joined(separator: " · "),
                           progress: $0.progress, transcoding: $0.isTranscoding)
            }
            return [.streams(streams),
                    .stat(ServiceStat(instanceName: instance.name, type: .tautulli,
                                      headline: "\(activity.count) Streaming",
                                      metrics: [Metric(label: "Active", value: "\(activity.count)")],
                                      instanceID: instance.id))]
        } catch {
            return [.stat(errorStat(instance, .tautulli, error))]
        }
    }

    nonisolated private static func loadJellystat(instance: ServiceInstance, client: JellystatClient) async -> [Contribution] {
        do {
            let sessions = try await client.sessions()
            let streams = sessions.map {
                StreamLine(title: $0.displayTitle,
                           subtitle: [$0.userName, $0.deviceName].compactMap { $0 }.joined(separator: " · "),
                           progress: $0.progress, transcoding: false)
            }
            return [.streams(streams),
                    .stat(ServiceStat(instanceName: instance.name, type: .jellystat,
                                      headline: "\(sessions.count) Streaming",
                                      metrics: [Metric(label: "Active", value: "\(sessions.count)")],
                                      instanceID: instance.id))]
        } catch {
            return [.stat(errorStat(instance, .jellystat, error))]
        }
    }

    nonisolated private static func loadQBittorrent(instance: ServiceInstance, client: QBittorrentClient) async -> [Contribution] {
        do {
            let torrents = try await client.torrents()
            let active = torrents.filter { !$0.isComplete && !$0.isPaused }.count
            let speed = (try? await client.transferInfo())?.dlInfoSpeed
            var metrics = [Metric(label: "Active", value: "\(active)")]
            if let speed { metrics.append(Metric(label: "Down", value: "\(Format.bytes(speed))/s")) }
            return [.stat(ServiceStat(instanceName: instance.name, type: .qbittorrent,
                                      headline: "\(torrents.count) Torrents", metrics: metrics,
                                      instanceID: instance.id))]
        } catch {
            return [.stat(errorStat(instance, .qbittorrent, error))]
        }
    }

    nonisolated private static func loadTransmission(instance: ServiceInstance, client: TransmissionClient) async -> [Contribution] {
        do {
            let torrents = try await client.torrents()
            let active = torrents.filter { $0.progress < 1 && !$0.isPaused }.count
            return [.stat(ServiceStat(instanceName: instance.name, type: .transmission,
                                      headline: "\(torrents.count) Torrents",
                                      metrics: [Metric(label: "Active", value: "\(active)")],
                                      instanceID: instance.id))]
        } catch {
            return [.stat(errorStat(instance, .transmission, error))]
        }
    }

    nonisolated private static func loadDeluge(instance: ServiceInstance, client: DelugeClient) async -> [Contribution] {
        do {
            let torrents = try await client.torrents()
            let active = torrents.filter { $0.fractionDone < 1 && !$0.isPaused }.count
            return [.stat(ServiceStat(instanceName: instance.name, type: .deluge,
                                      headline: "\(torrents.count) Torrents",
                                      metrics: [Metric(label: "Active", value: "\(active)")],
                                      instanceID: instance.id))]
        } catch {
            return [.stat(errorStat(instance, .deluge, error))]
        }
    }

    nonisolated private static func loadSABnzbd(instance: ServiceInstance, client: SABnzbdClient) async -> [Contribution] {
        do {
            let queue = try await client.queue()
            var metrics: [Metric] = []
            if let speed = queue.speed, !speed.isEmpty { metrics.append(Metric(label: "Speed", value: "\(speed)B/s")) }
            return [.stat(ServiceStat(instanceName: instance.name, type: .sabnzbd,
                                      headline: "\(queue.slots.count) Queued", metrics: metrics,
                                      instanceID: instance.id))]
        } catch {
            return [.stat(errorStat(instance, .sabnzbd, error))]
        }
    }

    nonisolated private static func loadNZBGet(instance: ServiceInstance, client: NZBGetClient) async -> [Contribution] {
        do {
            let groups = try await client.groups()
            return [.stat(ServiceStat(instanceName: instance.name, type: .nzbget,
                                      headline: "\(groups.count) Queued", metrics: [],
                                      instanceID: instance.id))]
        } catch {
            return [.stat(errorStat(instance, .nzbget, error))]
        }
    }

    nonisolated private static func loadProwlarr(instance: ServiceInstance, client: ProwlarrClient) async -> [Contribution] {
        var out: [Contribution] = []
        do {
            let indexers = try await client.indexers()
            let enabled = indexers.filter { $0.enable == true }.count
            out.append(.stat(ServiceStat(instanceName: instance.name, type: .prowlarr,
                                         headline: "\(indexers.count) Indexers",
                                         metrics: [Metric(label: "Enabled", value: "\(enabled)")])))
        } catch {
            out.append(.stat(errorStat(instance, .prowlarr, error)))
        }
        if let items = try? await client.health() {
            out.append(.health(items.compactMap { item in
                level(item.severity.rawValue).map { HealthLine(instanceName: instance.name, message: item.message ?? "—", level: $0) }
            }))
        }
        return out
    }

    nonisolated private static func loadBazarr(instance: ServiceInstance, client: BazarrClient) async -> [Contribution] {
        do {
            let badges = try await client.badges()
            return [.stat(ServiceStat(instanceName: instance.name, type: .bazarr,
                                      headline: "Subtitles",
                                      metrics: [Metric(label: "Episodes", value: "\(badges.episodes ?? 0)"),
                                                Metric(label: "Movies", value: "\(badges.movies ?? 0)")]))]
        } catch {
            return [.stat(errorStat(instance, .bazarr, error))]
        }
    }

    nonisolated private static func loadOverseerr(instance: ServiceInstance, client: OverseerrClient) async -> [Contribution] {
        do {
            let counts = try await client.requestCount()
            return [.stat(ServiceStat(instanceName: instance.name, type: .overseerr,
                                      headline: "\(counts.pending ?? 0) Pending",
                                      metrics: [Metric(label: "Total", value: "\(counts.total ?? 0)"),
                                                Metric(label: "Approved", value: "\(counts.approved ?? 0)")]))]
        } catch {
            return [.stat(errorStat(instance, .overseerr, error))]
        }
    }

    nonisolated private static func loadUnraid(instance: ServiceInstance, client: UnraidClient) async -> [Contribution] {
        do {
            let snapshot = try await client.snapshot()
            return [.stat(ServiceStat(instanceName: instance.name, type: .unraid,
                                      headline: "Array \(snapshot.array?.state ?? "—")",
                                      metrics: [Metric(label: "Containers", value: "\(snapshot.runningContainers)/\(snapshot.totalContainers)")]))]
        } catch {
            return [.stat(errorStat(instance, .unraid, error))]
        }
    }

    nonisolated private static func loadTorznab(instance: ServiceInstance, client: TorznabClient) async -> [Contribution] {
        do {
            let caps = try await client.capabilities()
            return [.stat(ServiceStat(instanceName: instance.name, type: instance.type,
                                      headline: caps.serverTitle ?? "Reachable",
                                      metrics: [Metric(label: "Categories", value: "\(caps.categoryCount)")]))]
        } catch {
            return [.stat(errorStat(instance, instance.type, error))]
        }
    }

    // MARK: - Helpers

    nonisolated private static func errorStat(_ instance: ServiceInstance, _ type: ServiceType, _ error: Error) -> ServiceStat {
        ServiceStat(instanceName: instance.name, type: type, headline: "Unavailable", metrics: [],
                    errorMessage: (error as? APIError)?.localizedDescription ?? error.localizedDescription)
    }

    nonisolated private static func level(_ severity: String) -> Level? {
        switch severity {
        case "notice": return .notice
        case "warning": return .warning
        case "error": return .error
        default: return nil
        }
    }
}

extension HomeViewModel.Level {
    var color: Color {
        switch self {
        case .notice: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
    var symbol: String {
        switch self {
        case .notice: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }
}
