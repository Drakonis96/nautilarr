import SwiftUI
import NautilarrCore
import SonarrKit
import RadarrKit
import LidarrKit

@MainActor
final class LibraryViewModel: ObservableObject {
    enum MonitoredFilter: String, CaseIterable, Identifiable {
        case all, monitored, unmonitored
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .monitored: return "Monitored"
            case .unmonitored: return "Unmonitored"
            }
        }
        func matches(_ entry: MediaEntry) -> Bool {
            switch self {
            case .all: return true
            case .monitored: return entry.isMonitored
            case .unmonitored: return !entry.isMonitored
            }
        }
    }

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all, downloaded, missing
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .downloaded: return "Downloaded"
            case .missing: return "Missing"
            }
        }
        func matches(_ entry: MediaEntry) -> Bool {
            switch self {
            case .all: return true
            case .downloaded: return entry.isComplete
            case .missing: return !entry.isComplete
            }
        }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case title, year, size, dateAdded
        var id: String { rawValue }
        var label: String {
            switch self {
            case .title: return "Title"
            case .year: return "Year"
            case .size: return "Size"
            case .dateAdded: return "Date Added"
            }
        }
        func sorted(_ entries: [MediaEntry]) -> [MediaEntry] {
            switch self {
            case .title: return entries.sorted { $0.sortKey < $1.sortKey }
            case .year: return entries.sorted { ($0.year ?? 0, $0.sortKey) > ($1.year ?? 0, $1.sortKey) }
            case .size: return entries.sorted { ($0.sizeOnDisk ?? 0) > ($1.sizeOnDisk ?? 0) }
            case .dateAdded: return entries.sorted { ($0.added ?? .distantPast) > ($1.added ?? .distantPast) }
            }
        }
    }

    @Published private(set) var entries: [MediaEntry] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""

    // Filters & sort.
    @Published var kindFilter: MediaKind?
    @Published var monitoredFilter: MonitoredFilter = .all
    @Published var statusFilter: StatusFilter = .all
    @Published var instanceFilter: UUID?
    @Published var genreFilter: String?
    @Published var qualityProfileFilter: String?
    @Published var sortOrder: SortOrder = .title

    /// Quality-profile names keyed by "instanceId-profileId", so library items
    /// (which only carry a profile id) can be filtered/labelled by profile name.
    @Published private(set) var qualityProfileNames: [String: String] = [:]

    /// Media kinds that have at least one configured instance.
    @Published var availableKinds: [MediaKind] = []
    var hasAny: Bool { !availableKinds.isEmpty }

    var isFiltering: Bool {
        monitoredFilter != .all || statusFilter != .all || instanceFilter != nil
            || genreFilter != nil || qualityProfileFilter != nil
    }

    // MARK: - Filter option sources (derived from the loaded entries)

    var availableInstances: [(id: UUID, name: String)] {
        var seen = Set<UUID>()
        var result: [(id: UUID, name: String)] = []
        for entry in entries where !seen.contains(entry.instance.id) {
            seen.insert(entry.instance.id)
            result.append((entry.instance.id, entry.instance.name))
        }
        return result.sorted { $0.name < $1.name }
    }

    var availableGenres: [String] {
        Array(Set(entries.flatMap(\.genres))).sorted()
    }

    var availableQualityProfiles: [String] {
        Array(Set(entries.compactMap(qualityProfileName(for:)))).sorted()
    }

    func qualityProfileName(for entry: MediaEntry) -> String? {
        guard let pid = entry.qualityProfileId else { return nil }
        return qualityProfileNames["\(entry.instance.id)-\(pid)"]
    }

    var filtered: [MediaEntry] {
        let result = entries.filter { entry in
            (kindFilter == nil || entry.kind == kindFilter)
            && (searchText.isEmpty || entry.title.localizedStandardContains(searchText))
            && monitoredFilter.matches(entry)
            && statusFilter.matches(entry)
            && (instanceFilter == nil || entry.instance.id == instanceFilter)
            && (genreFilter == nil || entry.genres.contains(genreFilter!))
            && (qualityProfileFilter == nil || qualityProfileName(for: entry) == qualityProfileFilter)
        }
        return sortOrder.sorted(result)
    }

    func clearFilters() {
        monitoredFilter = .all
        statusFilter = .all
        instanceFilter = nil
        genreFilter = nil
        qualityProfileFilter = nil
    }

    func load(store: InstanceStore) async {
        let sonarr = store.instances(ofType: .sonarr)
        let radarr = store.instances(ofType: .radarr)
        let lidarr = store.instances(ofType: .lidarr)

        var kinds: [MediaKind] = []
        if !sonarr.isEmpty { kinds.append(.series) }
        if !radarr.isEmpty { kinds.append(.movie) }
        if !lidarr.isEmpty { kinds.append(.artist) }
        availableKinds = kinds
        guard hasAny else { entries = []; return }

        if entries.isEmpty { isLoading = true }
        defer { isLoading = false }

        // Build the per-instance fetchers on the main actor (the store is
        // @MainActor), then run them all CONCURRENTLY so one slow/unreachable
        // instance can't block the others.
        var fetchers: [@Sendable () async -> (entries: [MediaEntry], error: String?)] = []
        for instance in sonarr {
            guard let client = store.sonarrClient(for: instance) else { continue }
            fetchers.append { await Self.fetch { try await client.series().map { .series(instance: instance, series: $0) } } }
        }
        for instance in radarr {
            guard let client = store.radarrClient(for: instance) else { continue }
            fetchers.append { await Self.fetch { try await client.movies().map { .movie(instance: instance, movie: $0) } } }
        }
        for instance in lidarr {
            guard let client = store.lidarrClient(for: instance) else { continue }
            fetchers.append { await Self.fetch { try await client.artists().map { .artist(instance: instance, artist: $0) } } }
        }

        let results = await withTaskGroup(of: (entries: [MediaEntry], error: String?).self) { group in
            for fetcher in fetchers { group.addTask { await fetcher() } }
            var all: [(entries: [MediaEntry], error: String?)] = []
            for await result in group { all.append(result) }
            return all
        }

        // If this load was cancelled mid-flight — which happens routinely when
        // the user switches tabs while the Library is reloading — every fetcher
        // returns empty with no error. Writing that through would blank an
        // already-populated grid (the "library vanished until I switch sections
        // and come back" bug). So: never clobber existing entries with an empty,
        // error-free result.
        let merged = results.flatMap(\.entries).sorted { $0.sortKey < $1.sortKey }
        let errors = results.compactMap(\.error)
        if Task.isCancelled || (merged.isEmpty && errors.isEmpty && !entries.isEmpty) {
            return
        }
        entries = merged
        // Only surface an error if NOTHING loaded; ignore cancellations.
        errorMessage = merged.isEmpty ? errors.first : nil

        await loadQualityProfiles(store: store, sonarr: sonarr, radarr: radarr, lidarr: lidarr)
    }

    /// Fetches quality-profile names for every loaded instance (concurrently), so
    /// the library can be filtered by profile.
    private func loadQualityProfiles(store: InstanceStore, sonarr: [ServiceInstance], radarr: [ServiceInstance], lidarr: [ServiceInstance]) async {
        var fetchers: [@Sendable () async -> (UUID, [(Int, String)])] = []
        for instance in sonarr {
            guard let client = store.sonarrClient(for: instance) else { continue }
            fetchers.append { (instance.id, ((try? await client.qualityProfiles()) ?? []).map { ($0.id, $0.name) }) }
        }
        for instance in radarr {
            guard let client = store.radarrClient(for: instance) else { continue }
            fetchers.append { (instance.id, ((try? await client.qualityProfiles()) ?? []).map { ($0.id, $0.name) }) }
        }
        for instance in lidarr {
            guard let client = store.lidarrClient(for: instance) else { continue }
            fetchers.append { (instance.id, ((try? await client.qualityProfiles()) ?? []).map { ($0.id, $0.name) }) }
        }
        let results = await withTaskGroup(of: (UUID, [(Int, String)]).self) { group in
            for fetcher in fetchers { group.addTask { await fetcher() } }
            var all: [(UUID, [(Int, String)])] = []
            for await result in group { all.append(result) }
            return all
        }
        var names: [String: String] = [:]
        for (instanceID, profiles) in results {
            for (pid, name) in profiles { names["\(instanceID)-\(pid)"] = name }
        }
        qualityProfileNames = names
    }

    /// Runs a fetch, returning its entries or a (non-cancellation) error string.
    private static func fetch(_ work: @Sendable () async throws -> [MediaEntry]) async -> (entries: [MediaEntry], error: String?) {
        do { return (try await work(), nil) }
        catch is CancellationError { return ([], nil) }
        catch let error as APIError where error == .cancelled { return ([], nil) }
        catch { return ([], (error as? APIError)?.localizedDescription ?? error.localizedDescription) }
    }
}
