import SwiftUI
import NautilarrCore
import OverseerrKit

/// A request enriched with its media title/poster for display.
struct RequestEntry: Identifiable {
    let instance: ServiceInstance
    let request: OverseerrRequest
    var title: String
    var posterPath: String?
    var id: String { "\(instance.id)-\(request.id)" }
}

@MainActor
final class RequestsViewModel: ObservableObject {
    @Published var entries: [RequestEntry] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasServices = true
    @Published var filter: String = "all"

    // Discover / create.
    @Published var searchText = ""
    @Published var searchResults: [OverseerrSearchResult] = []
    @Published var isSearching = false
    @Published var statusMessage: String?

    let filters = ["all", "pending", "approved", "available"]

    func load(store: InstanceStore) async {
        let instances = store.instances(ofType: .overseerr)
        hasServices = !instances.isEmpty
        guard hasServices else { entries = []; return }

        if entries.isEmpty { isLoading = true }
        defer { isLoading = false }

        var collected: [RequestEntry] = []
        var firstError: String?
        for instance in instances {
            guard let client = store.overseerrClient(for: instance) else { continue }
            do {
                let page = try await client.requests(take: 30, filter: filter)
                // Enrich titles/posters concurrently (best-effort).
                let enriched = await withTaskGroup(of: RequestEntry.self) { group -> [RequestEntry] in
                    for request in page.results {
                        group.addTask {
                            var title = "TMDB #\(request.media?.tmdbId ?? 0)"
                            var poster: String?
                            if let tmdbId = request.media?.tmdbId,
                               let details = try? await client.mediaDetails(mediaType: request.mediaType, tmdbId: tmdbId) {
                                title = details.displayTitle
                                poster = details.posterPath
                            }
                            return RequestEntry(instance: instance, request: request, title: title, posterPath: poster)
                        }
                    }
                    var results: [RequestEntry] = []
                    for await entry in group { results.append(entry) }
                    return results
                }
                collected += enriched.sorted { ($0.request.createdAt ?? .distantPast) > ($1.request.createdAt ?? .distantPast) }
            } catch {
                firstError = firstError ?? ((error as? APIError)?.localizedDescription ?? error.localizedDescription)
            }
        }
        entries = collected
        errorMessage = firstError
    }

    func approve(_ entry: RequestEntry, store: InstanceStore) async {
        guard let client = store.overseerrClient(for: entry.instance) else { return }
        _ = try? await client.approve(requestId: entry.request.id)
        await load(store: store)
    }

    func decline(_ entry: RequestEntry, store: InstanceStore) async {
        guard let client = store.overseerrClient(for: entry.instance) else { return }
        _ = try? await client.decline(requestId: entry.request.id)
        await load(store: store)
    }

    func deleteRequest(_ entry: RequestEntry, store: InstanceStore) async {
        guard let client = store.overseerrClient(for: entry.instance) else { return }
        _ = try? await client.deleteRequest(requestId: entry.request.id)
        await load(store: store)
    }

    // MARK: - Discover / create

    func search(store: InstanceStore) async {
        let term = searchText.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty,
              let instance = store.instances(ofType: .overseerr).first,
              let client = store.overseerrClient(for: instance) else { searchResults = []; return }
        isSearching = true
        defer { isSearching = false }
        searchResults = (try? await client.search(query: term)) ?? []
    }

    func request(_ result: OverseerrSearchResult, store: InstanceStore) async {
        guard let instance = store.instances(ofType: .overseerr).first,
              let client = store.overseerrClient(for: instance) else { return }
        do {
            try await client.createRequest(mediaType: result.mediaType ?? "movie", mediaId: result.id)
            statusMessage = "Requested “\(result.displayTitle)”."
        } catch {
            statusMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }
}
