import SwiftUI
import NautilarrCore
import SonarrKit

@MainActor
final class SeriesDetailViewModel: ObservableObject {
    @Published var episodesBySeason: [Int: [SonarrEpisode]] = [:]
    @Published var isLoading = false
    @Published var statusMessage: String?
    @Published var didDelete = false
    @Published var seriesMonitored: Bool
    @Published var seasons: [SonarrSeason]

    private let item: LibraryItem
    /// A mutable copy of the series, kept in sync as monitoring changes so season
    /// edits (which require a full-resource PUT) round-trip the latest state.
    private var series: SonarrSeries
    /// Set by the view once the environment is available (see `configure`).
    private weak var store: InstanceStore?
    private var client: SonarrClient? { store?.sonarrClient(for: item.instance) }

    init(item: LibraryItem) {
        self.item = item
        self.series = item.series
        self.seriesMonitored = item.series.monitored ?? false
        self.seasons = item.series.seasons ?? []
    }

    /// Injects the environment store. Safe to call repeatedly.
    func configure(store: InstanceStore) {
        self.store = store
    }

    var seasonNumbers: [Int] {
        episodesBySeason.keys.sorted(by: >)
    }

    func loadEpisodes() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let episodes = try await client.episodes(seriesId: item.series.id)
            episodesBySeason = Dictionary(grouping: episodes) { $0.seasonNumber ?? 0 }
        } catch {
            statusMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }

    func automaticSearchSeries() async {
        await runCommand(.seriesSearch(seriesId: item.series.id), success: "Searching all monitored episodes…")
    }

    func searchSeason(_ seasonNumber: Int) async {
        await runCommand(.seasonSearch(seriesId: item.series.id, seasonNumber: seasonNumber),
                         success: "Searching season \(seasonNumber)…")
    }

    func refresh() async {
        await runCommand(.refreshSeries(seriesId: item.series.id), success: "Refreshing series metadata…")
    }

    private func runCommand(_ command: SonarrCommandRequest, success: String) async {
        guard let client else { return }
        do {
            _ = try await client.runCommand(command)
            statusMessage = success
        } catch {
            statusMessage = describe(error)
        }
    }

    // MARK: - Monitoring

    func setSeriesMonitored(_ value: Bool) async {
        seriesMonitored = value
        guard let client else { return }
        do {
            try await client.editSeries(ids: [series.id], monitored: value)
            series.monitored = value
            statusMessage = value ? "Now monitoring series." : "Series unmonitored."
        } catch {
            seriesMonitored = !value
            statusMessage = describe(error)
        }
    }

    func isSeasonMonitored(_ seasonNumber: Int) -> Bool {
        seasons.first { $0.seasonNumber == seasonNumber }?.monitored ?? false
    }

    /// Season monitoring isn't covered by the editor endpoint, so flip the flag
    /// on the full series and PUT it back.
    func setSeasonMonitored(_ seasonNumber: Int, monitored: Bool) async {
        guard let client else { return }
        setSeasonMonitoredLocally(seasonNumber, monitored: monitored)
        var updated = series
        if let idx = updated.seasons?.firstIndex(where: { $0.seasonNumber == seasonNumber }) {
            updated.seasons?[idx].monitored = monitored
        }
        do {
            let saved = try await client.updateSeries(updated)
            series = saved
            if let savedSeasons = saved.seasons { seasons = savedSeasons }
            statusMessage = "Season \(seasonNumber) \(monitored ? "monitored" : "unmonitored")."
        } catch {
            setSeasonMonitoredLocally(seasonNumber, monitored: !monitored)
            statusMessage = describe(error)
        }
    }

    func setEpisodeMonitored(_ episode: SonarrEpisode, monitored: Bool) async {
        guard let client else { return }
        setEpisodeMonitoredLocally(episode.id, monitored: monitored)
        do {
            try await client.setEpisodesMonitored(ids: [episode.id], monitored: monitored)
        } catch {
            setEpisodeMonitoredLocally(episode.id, monitored: !monitored)
            statusMessage = describe(error)
        }
    }

    private func setSeasonMonitoredLocally(_ seasonNumber: Int, monitored: Bool) {
        if let i = seasons.firstIndex(where: { $0.seasonNumber == seasonNumber }) {
            seasons[i].monitored = monitored
        }
    }

    private func setEpisodeMonitoredLocally(_ id: Int, monitored: Bool) {
        for (season, eps) in episodesBySeason {
            if let i = eps.firstIndex(where: { $0.id == id }) {
                episodesBySeason[season]?[i].monitored = monitored
            }
        }
    }

    private func describe(_ error: Error) -> String {
        (error as? APIError)?.localizedDescription ?? error.localizedDescription
    }

    func delete(deleteFiles: Bool) async {
        guard let client else { return }
        do {
            try await client.deleteSeries(id: item.series.id, deleteFiles: deleteFiles)
            didDelete = true
        } catch {
            statusMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }

    /// Interactive-search loader for a single episode. Surfaces failures (the
    /// shared results view shows the real error) instead of swallowing them — the
    /// previous `try?` made every failure read as "No releases found", which is
    /// why series/episode search appeared broken while movies worked.
    func episodeSearchLoader(_ episode: SonarrEpisode) -> () async throws -> [InteractiveRelease] {
        guard let client else { return { throw APIError.invalidResponse } }
        return InteractiveSearchLoader.sonarrEpisode(client, episodeId: episode.id)
    }

    /// Interactive-search loader for a whole-season pack.
    func seasonSearchLoader(seriesId: Int, seasonNumber: Int) -> () async throws -> [InteractiveRelease] {
        guard let client else { return { throw APIError.invalidResponse } }
        return InteractiveSearchLoader.sonarrSeason(client, seriesId: seriesId, seasonNumber: seasonNumber)
    }

    /// Automatic (indexer) search for a single episode. Returns a status string
    /// for the caller's toast.
    func automaticSearchEpisode(_ episode: SonarrEpisode) async -> String {
        guard let client else { return "No service" }
        do {
            _ = try await client.runCommand(.episodeSearch(episodeIds: [episode.id]))
            return "Searching for this episode…"
        } catch {
            return describe(error)
        }
    }
}
