import SwiftUI
import NautilarrCore
import OverseerrKit
import SonarrKit
import RadarrKit

/// One title followed end-to-end: request → grab → download → import → available.
struct PipelineItem: Identifiable {
    let id: String
    let title: String
    let posterPath: String?
    let mediaType: String          // "movie" | "tv"
    let requestedBy: String?
    let stage: PipelineStage
    let progress: Double           // 0…1 for the active stage
    /// The library item to open on tap, when we could resolve it from the queue.
    let mediaEntry: MediaEntry?
}

/// Builds the request pipeline by correlating Overseerr/Jellyseerr requests with
/// the live Sonarr/Radarr download queues (matched on tmdbId, with a normalised
/// title fallback). Title/poster lookups are cached so refreshes stay cheap.
@MainActor
final class PipelineViewModel: ObservableObject {
    @Published var items: [PipelineItem] = []
    @Published var isLoading = false
    @Published var hasServices = true

    /// tmdbId → (title, poster) from Overseerr media details, cached across refreshes.
    private var detailCache: [Int: (title: String, poster: String?)] = [:]

    func load(store: InstanceStore) async {
        let overseerr = store.instances(ofType: .overseerr)
        hasServices = !overseerr.isEmpty
        guard hasServices else { items = []; return }

        if items.isEmpty { isLoading = true }
        defer { isLoading = false }

        // 1. Build queue match maps from every Sonarr/Radarr instance (by tmdbId
        //    and by normalised title), plus a MediaEntry for navigation.
        var tmdbMatches: [Int: [PipelineQueueMatch]] = [:]
        var titleMatches: [String: [PipelineQueueMatch]] = [:]
        var tmdbEntry: [Int: MediaEntry] = [:]
        var titleEntry: [String: MediaEntry] = [:]

        for instance in store.instances(ofType: .radarr) {
            guard let client = store.radarrClient(for: instance) else { continue }
            guard let queue = try? await client.queue(pageSize: 200) else { continue }
            for item in queue.records {
                let m = PipelineQueueMatch(progress: item.progress,
                                           trackedState: item.trackedDownloadState ?? item.status ?? "",
                                           hasError: item.trackedDownloadStatus?.lowercased() == "error")
                if let movie = item.movie {
                    if let tmdb = movie.tmdbId {
                        tmdbMatches[tmdb, default: []].append(m)
                        tmdbEntry[tmdb] = .movie(instance: instance, movie: movie)
                    }
                    let key = PipelineCorrelator.matchKey(title: movie.title, year: nil)
                    titleMatches[key, default: []].append(m)
                    titleEntry[key] = .movie(instance: instance, movie: movie)
                }
            }
        }
        for instance in store.instances(ofType: .sonarr) {
            guard let client = store.sonarrClient(for: instance) else { continue }
            guard let queue = try? await client.queue(pageSize: 200) else { continue }
            for item in queue.records {
                let m = PipelineQueueMatch(progress: item.progress,
                                           trackedState: item.trackedDownloadState ?? item.status ?? "",
                                           hasError: item.trackedDownloadStatus?.lowercased() == "error")
                if let series = item.series {
                    if let tmdb = series.tmdbId {
                        tmdbMatches[tmdb, default: []].append(m)
                        tmdbEntry[tmdb] = .series(instance: instance, series: series)
                    }
                    let key = PipelineCorrelator.matchKey(title: series.title, year: nil)
                    titleMatches[key, default: []].append(m)
                    titleEntry[key] = .series(instance: instance, series: series)
                }
            }
        }

        // 2. Pull every request and place it on the pipeline.
        var collected: [PipelineItem] = []
        for instance in overseerr {
            guard let client = store.overseerrClient(for: instance) else { continue }
            guard let page = try? await client.requests(take: 50, filter: "all") else { continue }
            for request in page.results {
                guard PipelineCorrelator.isVisible(requestStatus: request.status.rawValue) else { continue }
                let tmdb = request.media?.tmdbId
                let (title, poster) = await detail(for: request, client: client)

                // Correlate: tmdbId first, then normalised title.
                let titleKey = PipelineCorrelator.matchKey(title: title, year: nil)
                let matches = (tmdb.flatMap { tmdbMatches[$0] }) ?? titleMatches[titleKey]
                let entry = (tmdb.flatMap { tmdbEntry[$0] }) ?? titleEntry[titleKey]
                let best = PipelineQueueMatch.best(matches ?? [])

                let placed = PipelineCorrelator.stage(
                    requestStatus: request.status.rawValue,
                    mediaStatus: request.media?.status,
                    match: best)

                collected.append(PipelineItem(
                    id: "\(instance.id)-\(request.id)", title: title, posterPath: poster,
                    mediaType: request.mediaType, requestedBy: request.requestedBy?.name,
                    stage: placed.stage, progress: placed.progress, mediaEntry: entry))
            }
        }

        // Active items first (lowest completed stage), available last; newest-ish order within.
        items = collected.sorted {
            if $0.stage != $1.stage { return $0.stage < $1.stage }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    /// Title + poster for a request, cached by tmdbId to avoid re-fetching.
    private func detail(for request: OverseerrRequest, client: OverseerrClient) async -> (String, String?) {
        guard let tmdb = request.media?.tmdbId else { return ("Untitled request", nil) }
        if let cached = detailCache[tmdb] { return (cached.title, cached.poster) }
        if let details = try? await client.mediaDetails(mediaType: request.mediaType, tmdbId: tmdb) {
            detailCache[tmdb] = (details.displayTitle, details.posterPath)
            return (details.displayTitle, details.posterPath)
        }
        return ("TMDB #\(tmdb)", nil)
    }
}
