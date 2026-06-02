import Foundation
import NautilarrCore
import SonarrKit
import RadarrKit
import LidarrKit

/// Performs management actions (search, refresh, monitor, delete) against the
/// correct *arr client for a `MediaEntry`, so the library list, context menus
/// and bulk-selection toolbar can share one code path.
///
/// Every call returns an optional error string — `nil` means success.
enum LibraryActions {

    // MARK: - Single item

    @MainActor
    static func automaticSearch(_ entry: MediaEntry, store: InstanceStore) async -> String? {
        switch entry {
        case let .series(instance, series):
            guard let c = store.sonarrClient(for: instance) else { return noClient }
            return await run { _ = try await c.runCommand(.seriesSearch(seriesId: series.id)) }
        case let .movie(instance, movie):
            guard let c = store.radarrClient(for: instance) else { return noClient }
            return await run { _ = try await c.runCommand(.movieSearch(movieId: movie.id)) }
        case let .artist(instance, artist):
            guard let c = store.lidarrClient(for: instance) else { return noClient }
            return await run { _ = try await c.runCommand(.artistSearch(artistId: artist.id)) }
        }
    }

    @MainActor
    static func refresh(_ entry: MediaEntry, store: InstanceStore) async -> String? {
        switch entry {
        case let .series(instance, series):
            guard let c = store.sonarrClient(for: instance) else { return noClient }
            return await run { _ = try await c.runCommand(.refreshSeries(seriesId: series.id)) }
        case let .movie(instance, movie):
            guard let c = store.radarrClient(for: instance) else { return noClient }
            return await run { _ = try await c.runCommand(.refreshMovie(movieId: movie.id)) }
        case let .artist(instance, artist):
            guard let c = store.lidarrClient(for: instance) else { return noClient }
            return await run { _ = try await c.runCommand(.refreshArtist(artistId: artist.id)) }
        }
    }

    @MainActor
    static func setMonitored(_ entry: MediaEntry, monitored: Bool, store: InstanceStore) async -> String? {
        switch entry {
        case let .series(instance, series):
            guard let c = store.sonarrClient(for: instance) else { return noClient }
            return await run { try await c.editSeries(ids: [series.id], monitored: monitored) }
        case let .movie(instance, movie):
            guard let c = store.radarrClient(for: instance) else { return noClient }
            return await run { try await c.editMovies(ids: [movie.id], monitored: monitored) }
        case let .artist(instance, artist):
            guard let c = store.lidarrClient(for: instance) else { return noClient }
            return await run { try await c.editArtists(ids: [artist.id], monitored: monitored) }
        }
    }

    @MainActor
    static func delete(_ entry: MediaEntry, deleteFiles: Bool, store: InstanceStore) async -> String? {
        switch entry {
        case let .series(instance, series):
            guard let c = store.sonarrClient(for: instance) else { return noClient }
            return await run { try await c.deleteSeries(id: series.id, deleteFiles: deleteFiles) }
        case let .movie(instance, movie):
            guard let c = store.radarrClient(for: instance) else { return noClient }
            return await run { try await c.deleteMovie(id: movie.id, deleteFiles: deleteFiles) }
        case let .artist(instance, artist):
            guard let c = store.lidarrClient(for: instance) else { return noClient }
            return await run { try await c.deleteArtist(id: artist.id, deleteFiles: deleteFiles) }
        }
    }

    // MARK: - Bulk

    /// Bulk monitored toggle. Grouped by instance so each service receives a
    /// single editor call.
    @MainActor
    static func setMonitored(_ entries: [MediaEntry], monitored: Bool, store: InstanceStore) async -> String? {
        var firstError: String?
        for group in groupedByInstance(entries) {
            guard let probe = group.first else { continue }
            let ids = group.map(\.mediaId)
            let err: String?
            switch probe {
            case let .series(instance, _):
                if let c = store.sonarrClient(for: instance) {
                    err = await run { try await c.editSeries(ids: ids, monitored: monitored) }
                } else { err = noClient }
            case let .movie(instance, _):
                if let c = store.radarrClient(for: instance) {
                    err = await run { try await c.editMovies(ids: ids, monitored: monitored) }
                } else { err = noClient }
            case let .artist(instance, _):
                if let c = store.lidarrClient(for: instance) {
                    err = await run { try await c.editArtists(ids: ids, monitored: monitored) }
                } else { err = noClient }
            }
            firstError = firstError ?? err
        }
        return firstError
    }

    /// Bulk automatic search (one command per item).
    @MainActor
    static func automaticSearch(_ entries: [MediaEntry], store: InstanceStore) async -> String? {
        var firstError: String?
        for entry in entries {
            let err = await automaticSearch(entry, store: store)
            if firstError == nil { firstError = err }
        }
        return firstError
    }

    /// Bulk refresh (one command per item).
    @MainActor
    static func refresh(_ entries: [MediaEntry], store: InstanceStore) async -> String? {
        var firstError: String?
        for entry in entries {
            let err = await refresh(entry, store: store)
            if firstError == nil { firstError = err }
        }
        return firstError
    }

    // MARK: - Helpers

    private static let noClient = "Service unavailable"

    private static func groupedByInstance(_ entries: [MediaEntry]) -> [[MediaEntry]] {
        Array(Dictionary(grouping: entries, by: { $0.instance.id }).values)
    }

    private static func run(_ work: () async throws -> Void) async -> String? {
        do { try await work(); return nil }
        catch { return (error as? APIError)?.localizedDescription ?? error.localizedDescription }
    }
}
